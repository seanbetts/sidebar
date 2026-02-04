import Foundation
import sideBarShared
import Combine
import Supabase
import os

// MARK: - SupabaseAuthAdapter

/// Represents AuthErrorEvent.
public struct AuthErrorEvent: Equatable {
    public let id = UUID()
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

/// Defines AuthAdapterError.
public enum AuthAdapterError: LocalizedError, Equatable {
    case signInInProgress
    case invalidCredentials
    case rateLimited
    case serviceUnavailable
    case networkUnavailable
    case sessionRefreshFailed
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .signInInProgress:
            return "A sign-in request is already in progress."
        case .invalidCredentials:
            return "Email or password is incorrect."
        case .rateLimited:
            return "Too many login attempts. Please wait a moment and try again."
        case .serviceUnavailable:
            return "Service temporarily unavailable. Please try again later."
        case .networkUnavailable:
            return "You're offline. Check your connection and try again."
        case .sessionRefreshFailed:
            return "We couldn't refresh your session. Please sign in again."
        case .unknown(let message):
            return message
        }
    }
}

@MainActor
/// Supabase-backed authentication session handler.
public final class SupabaseAuthAdapter: ObservableObject, AuthSession {
    @Published public private(set) var accessToken: String?
    @Published public private(set) var userId: String?
    @Published public private(set) var authState: AuthState = .signedOut
    @Published public private(set) var authError: AuthErrorEvent?

    private let stateStore: AuthStateStore
    private let authClient: SupabaseAuthClientProtocol
    private var authStateTask: Task<Void, Never>?
    private var refreshInFlightTask: Task<Void, Never>?
    private var signInTask: Task<Void, Error>?
    private let logger = Logger(subsystem: "sideBar", category: "Auth")
    private let sessionRefreshLeadTime: TimeInterval = 600  // 10 min before expiry
    private let refreshCooldown: TimeInterval = 60
    private let offlineAccessWindow: TimeInterval = 60 * 60 * 24
    private let lastAuthTimestampKey = AppStorageKeys.lastAuthTimestamp
    private var lastSessionExpiryDate: Date?
    private var lastRefreshAttempt: Date?

    // Rate limiting for login attempts
    private var failedLoginAttempts: Int = 0
    private var lockoutEndTime: Date?
    private let maxFailedAttempts: Int = 5
    private let lockoutDuration: TimeInterval = 300  // 5 minutes

    /// Returns true if the user is locked out due to too many failed login attempts
    public var isLockedOut: Bool {
        guard let endTime = lockoutEndTime else { return false }
        if Date() >= endTime {
            // Lockout expired, reset state
            lockoutEndTime = nil
            failedLoginAttempts = 0
            return false
        }
        return true
    }

    /// Returns remaining lockout time in seconds, or nil if not locked out
    public var lockoutRemainingSeconds: Int? {
        guard let endTime = lockoutEndTime else { return nil }
        let remaining = Int(endTime.timeIntervalSinceNow)
        return remaining > 0 ? remaining : nil
    }

    public var authorizationToken: String? {
        authState == .active ? accessToken : nil
    }

    public init(
        config: EnvironmentConfig,
        stateStore: AuthStateStore,
        startAuthStateTask: Bool = true
    ) {
        // Create Supabase storage adapter using our Keychain store.
        // This eliminates the race condition between Supabase's internal storage
        // and our separate Keychain storage by making them the same.
        let authOptions: SupabaseClientOptions.AuthOptions
        if let keychainStore = stateStore as? KeychainAuthStateStore {
            authOptions = SupabaseClientOptions.AuthOptions(
                storage: SupabaseKeychainStorage(stateStore: keychainStore),
                emitLocalSessionAsInitialSession: true
            )
        } else {
            authOptions = SupabaseClientOptions.AuthOptions(
                emitLocalSessionAsInitialSession: true
            )
        }

        let supabase = SupabaseClient(
            supabaseURL: config.supabaseUrl,
            supabaseKey: config.supabaseAnonKey,
            options: SupabaseClientOptions(auth: authOptions)
        )
        self.stateStore = stateStore
        self.authClient = SupabaseAuthClient(supabase: supabase)
        commonInit(startAuthStateTask: startAuthStateTask)
    }

    init(
        authClient: SupabaseAuthClientProtocol,
        stateStore: AuthStateStore,
        startAuthStateTask: Bool = true
    ) {
        self.stateStore = stateStore
        self.authClient = authClient
        commonInit(startAuthStateTask: startAuthStateTask)
    }

    private func commonInit(startAuthStateTask: Bool) {
        // With unified storage, Supabase now loads sessions from our Keychain automatically.
        // We just need to apply the session if one exists, or check offline window expiry.
        if let session = authClient.currentSession {
            if shouldAllowOfflineAccess(hasStoredToken: true) {
                applySession(session)
            } else {
                // Offline window expired - attempt recovery before clearing
                Task { [weak self] in
                    await self?.attemptSessionRecovery()
                }
            }
        }

        if startAuthStateTask {
            authStateTask = Task { [authClient, weak self] in
                for await (event, session) in authClient.authStateChanges {
                    guard let self else { return }
                    await self.handleAuthStateChange(event: event, session: session)
                }
            }
        }
    }

    deinit {
        authStateTask?.cancel()
        refreshInFlightTask?.cancel()
    }

    public func signIn(email: String, password: String) async throws {
        // Check rate limiting
        if isLockedOut {
            throw AuthAdapterError.rateLimited
        }

        guard signInTask == nil else {
            throw AuthAdapterError.signInInProgress
        }
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.authClient.signIn(email: email, password: password)
                if let session = self.authClient.currentSession {
                    self.applySession(session)
                }
                // Reset rate limiting on successful login
                self.failedLoginAttempts = 0
                self.lockoutEndTime = nil
                self.logger.notice("Sign in succeeded")
            } catch {
                // Track failed attempts for rate limiting
                self.failedLoginAttempts += 1
                if self.failedLoginAttempts >= self.maxFailedAttempts {
                    self.lockoutEndTime = Date().addingTimeInterval(self.lockoutDuration)
                    self.logger.warning("Login rate limit exceeded, locked out for \(Int(self.lockoutDuration))s")
                }

                let mappedError = self.mapAuthError(error)
                self.logger.error("Sign in failed: \(mappedError.localizedDescription, privacy: .public)")
                throw mappedError
            }
        }
        signInTask = task
        defer { signInTask = nil }
        try await task.value
    }

    /// Refreshes session only if close to expiry (avoids unnecessary refreshes on foreground)
    public func refreshSessionIfStale() async {
        guard let expiry = lastSessionExpiryDate,
              expiry.timeIntervalSinceNow < sessionRefreshLeadTime else { return }
        await refreshSession()
    }

    public func refreshSession() async {
        guard authClient.currentSession != nil else {
            return
        }
        if let task = refreshInFlightTask {
            _ = await task.value
            return
        }
        let now = Date()
        if let lastRefreshAttempt, now.timeIntervalSince(lastRefreshAttempt) < refreshCooldown {
            return
        }
        lastRefreshAttempt = now
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let session = try await self.authClient.refreshSession()
                self.applySession(session)
                self.logger.notice("Session refresh succeeded")
            } catch {
                self.logger.error("Session refresh failed: \(error.localizedDescription, privacy: .public)")
                if self.isAuthInvalid(error) {
                    await self.transitionToSignedOut(clearPersistedState: true)
                    self.recordError(AuthAdapterError.sessionRefreshFailed.errorDescription ?? "Session refresh failed.")
                } else {
                    self.transitionToStale()
                }
            }
        }
        refreshInFlightTask = task
        defer { refreshInFlightTask = nil }
        _ = await task.value
    }

    public func signOut() async {
        do {
            try await authClient.signOut()
        } catch {
            // Best effort: clear local auth even if server sign-out fails.
        }
        await transitionToSignedOut(clearPersistedState: true)
    }

    public func restoreSession(accessToken: String?, userId: String?) {
        self.accessToken = accessToken
        self.userId = userId
        do {
            try stateStore.saveAccessToken(accessToken)
            try stateStore.saveUserId(userId)
        } catch {
            recordError("Unable to save authentication state.")
        }
    }

    public var canRestoreOfflineSession: Bool {
        do {
            let storedToken = try stateStore.loadAccessToken()
            let storedUserId = try stateStore.loadUserId()
            guard storedToken != nil, storedUserId != nil else { return false }
            return shouldAllowOfflineAccess(hasStoredToken: true)
        } catch {
            return false
        }
    }

    @discardableResult
    public func restoreOfflineSession() -> Bool {
        do {
            let storedToken = try stateStore.loadAccessToken()
            let storedUserId = try stateStore.loadUserId()
            guard let storedToken, let storedUserId else { return false }
            guard shouldAllowOfflineAccess(hasStoredToken: true) else { return false }
            restoreSession(accessToken: storedToken, userId: storedUserId)
            transitionToStale()
            return true
        } catch {
            return false
        }
    }

    private func applySession(_ session: SupabaseSessionInfo?) {
        guard let session else { return }
        let resolvedExpiry = Self.sessionExpiryDate(from: session)
        if resolvedExpiry <= Date() {
            // Keep the user "signed in" locally while we attempt a silent refresh.
            restoreSession(accessToken: session.accessToken, userId: session.userId)
            lastSessionExpiryDate = resolvedExpiry
            transitionToStale()
            Task { await refreshSession() }
            return
        }

        restoreSession(accessToken: session.accessToken, userId: session.userId)
        updateLastAuthTimestamp(Date())
        lastSessionExpiryDate = resolvedExpiry
        authState = .active
    }

    private func mapAuthError(_ error: Error) -> AuthAdapterError {
        if let authError = error as? AuthAdapterError {
            return authError
        }
        if error is URLError {
            return .networkUnavailable
        }

        let description = error.localizedDescription.lowercased()
        if description.contains("invalid") && description.contains("credentials") {
            return .invalidCredentials
        }
        if description.contains("too many") && description.contains("request") {
            return .rateLimited
        }
        if description.contains("rate") && description.contains("limit") {
            return .rateLimited
        }
        if description.contains("service") && description.contains("unavailable") {
            return .serviceUnavailable
        }
        return .unknown(error.localizedDescription)
    }

    static func sessionExpiryDate(from session: SupabaseSessionInfo) -> Date {
        if let jwtExpiry = jwtExpiryDate(from: session.accessToken) {
            return jwtExpiry
        }
        return resolveExpiryDate(from: session.expiresAt)
    }

    static func jwtExpiryDate(from accessToken: String) -> Date? {
        guard let payloadData = decodeJwtPayload(accessToken) else {
            return nil
        }
        guard
            let jsonObject = try? JSONSerialization.jsonObject(with: payloadData, options: []),
            let payload = jsonObject as? [String: Any]
        else {
            return nil
        }
        if let exp = payload["exp"] as? TimeInterval {
            return Date(timeIntervalSince1970: exp)
        }
        if let expString = payload["exp"] as? String,
           let exp = TimeInterval(expString) {
            return Date(timeIntervalSince1970: exp)
        }
        return nil
    }

    private static func decodeJwtPayload(_ token: String) -> Data? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        let payload = String(segments[1])
        return base64UrlDecode(payload)
    }

    private static func base64UrlDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = 4 - (base64.count % 4)
        if padding < 4 {
            base64.append(String(repeating: "=", count: padding))
        }
        return Data(base64Encoded: base64)
    }

    private static func resolveExpiryDate(from expiresAt: TimeInterval) -> Date {
        let epochThreshold: TimeInterval = 1_000_000_000
        if expiresAt > epochThreshold {
            return Date(timeIntervalSince1970: expiresAt)
        }
        return Date(timeIntervalSinceNow: max(expiresAt, 0))
    }

    private func shouldAllowOfflineAccess(hasStoredToken: Bool) -> Bool {
        let lastAuthTimestamp = UserDefaults.standard.double(forKey: lastAuthTimestampKey)
        if lastAuthTimestamp == 0, hasStoredToken {
            updateLastAuthTimestamp(Date())
            return true
        }
        guard lastAuthTimestamp > 0 else { return false }
        let lastAuthDate = Date(timeIntervalSince1970: lastAuthTimestamp)
        return Date().timeIntervalSince(lastAuthDate) <= offlineAccessWindow
    }

    /// Attempts to recover a session when the offline access window has expired.
    /// On success, applies the refreshed session. On failure, signs out.
    private func attemptSessionRecovery() async {
        do {
            guard authClient.currentSession != nil else {
                await transitionToSignedOut(clearPersistedState: true)
                return
            }
            let session = try await authClient.refreshSession()
            applySession(session)
            logger.notice("Session recovery succeeded after offline window expiry")
        } catch {
            logger.warning("Session recovery failed: \(error.localizedDescription, privacy: .public)")
            if isAuthInvalid(error) {
                await transitionToSignedOut(clearPersistedState: true)
            } else {
                transitionToStale()
            }
        }
    }

    private func updateLastAuthTimestamp(_ date: Date) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: lastAuthTimestampKey)
    }

    private func recordError(_ message: String) {
        logger.error("\(message, privacy: .public)")
        authError = AuthErrorEvent(message: message)
    }

    public func clearAuthError() {
        authError = nil
    }

    private func transitionToStale() {
        if authState != .stale {
            logger.notice("Auth state transitioned to stale")
        }
        authState = .stale
    }

    private func transitionToSignedOut(clearPersistedState: Bool) async {
        accessToken = nil
        userId = nil
        lastSessionExpiryDate = nil
        refreshInFlightTask?.cancel()
        if clearPersistedState {
            do {
                try stateStore.clear()
            } catch {
                logger.error("Failed to clear auth state: \(error.localizedDescription, privacy: .public)")
            }
        }
        authState = .signedOut
        logger.notice("Signed out")
    }

    private func handleAuthStateChange(event: SupabaseAuthEvent, session: SupabaseSessionInfo?) async {
        switch event {
        case .signedOut:
            await transitionToSignedOut(clearPersistedState: true)
        case .initialSession:
            if let session {
                applySession(session)
            } else {
                // INITIAL_SESSION can legitimately be nil; attempt recovery only if we were previously signed in.
                if authState != .signedOut {
                    await attemptSessionRecovery()
                }
            }
        case .other:
            if let session {
                applySession(session)
                return
            }
            // Treat nil as "unknown" and attempt recovery once, then decide.
            await attemptSessionRecovery()
        }
    }

    private func isAuthInvalid(_ error: Error) -> Bool {
        if error is URLError {
            return false
        }
        let description = error.localizedDescription.lowercased()
        if description.contains("invalid") && description.contains("refresh") {
            return true
        }
        if description.contains("refresh token") && description.contains("expired") {
            return true
        }
        if description.contains("jwt") && description.contains("expired") && description.contains("refresh") {
            return true
        }
        if description.contains("unauthorized") || description.contains("forbidden") {
            return true
        }
        return false
    }
}
