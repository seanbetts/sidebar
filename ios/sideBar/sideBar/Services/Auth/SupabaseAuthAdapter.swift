import Foundation
@preconcurrency import sideBarShared
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
    case weakPassword
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
        case .weakPassword:
            return "Password must be at least 8 characters."
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
public final class SupabaseAuthAdapter: ObservableObject, AuthSession, AuthSessionInvalidating {
    @Published public private(set) var accessToken: String?
    @Published public private(set) var userId: String?
    @Published public private(set) var authState: AuthState = .signedOut
    @Published public internal(set) var authError: AuthErrorEvent?
    @Published public internal(set) var pendingVerificationEmail: String?

    let stateStore: AuthStateStore
    let authClient: SupabaseAuthClientProtocol
    private var authStateTask: Task<Void, Never>?
    private var refreshInFlightTask: Task<Void, Never>?
    private var signInTask: Task<Void, Error>?
    let userDefaults: UserDefaults
    let logger = Logger(subsystem: "sideBar", category: "Auth")
    private let statePersistenceQueue = DispatchQueue(
        label: "ai.sidebar.sidebar.auth-state-persistence",
        qos: .utility
    )
    private let sessionRefreshLeadTime: TimeInterval = 600  // 10 min before expiry
    private let refreshCooldown: TimeInterval = 60
    let offlineAccessWindow: TimeInterval = 60 * 60 * 24
    let lastAuthTimestampKey = AppStorageKeys.lastAuthTimestamp
    let failedLoginAttemptsKey = AppStorageKeys.failedLoginAttempts
    let lockoutEndTimeKey = AppStorageKeys.lockoutEndTime
    private var lastSessionExpiryDate: Date?
    private var lastRefreshAttempt: Date?
    // Rate limiting for login attempts
    var failedLoginAttempts: Int = 0
    var lockoutEndTime: Date?
    private let maxFailedAttempts: Int = 5
    private let lockoutDuration: TimeInterval = 300  // 5 minutes

    /// Returns true if the user is locked out due to too many failed login attempts
    public var isLockedOut: Bool {
        guard let endTime = lockoutEndTime else { return false }
        if Date() >= endTime {
            // Lockout expired, reset state
            lockoutEndTime = nil
            failedLoginAttempts = 0
            persistRateLimitState()
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
        startAuthStateTask: Bool = true,
        userDefaults: UserDefaults = .standard
    ) {
        let authOptions = Self.makeAuthOptions(stateStore: stateStore)
        let supabase = SupabaseClient(
            supabaseURL: config.supabaseUrl,
            supabaseKey: config.supabaseAnonKey,
            options: SupabaseClientOptions(auth: authOptions)
        )
        self.stateStore = stateStore
        self.authClient = SupabaseAuthClient(supabase: supabase)
        self.userDefaults = userDefaults
        commonInit(startAuthStateTask: startAuthStateTask)
    }

    static func makeAuthOptions(stateStore: AuthStateStore) -> SupabaseClientOptions.AuthOptions {
        // Keep Supabase session storage aligned with the injected auth store.
        // Non-keychain stores must use in-memory storage so tests/previews never
        // accidentally load an existing device keychain session.
        if let keychainStore = stateStore as? KeychainAuthStateStore {
            return SupabaseClientOptions.AuthOptions(
                storage: SupabaseKeychainStorage(stateStore: keychainStore),
                flowType: .implicit,
                emitLocalSessionAsInitialSession: true
            )
        }
        return SupabaseClientOptions.AuthOptions(
            storage: SupabaseInMemoryStorage(),
            flowType: .implicit,
            emitLocalSessionAsInitialSession: true
        )
    }

    init(
        authClient: SupabaseAuthClientProtocol,
        stateStore: AuthStateStore,
        startAuthStateTask: Bool = true,
        userDefaults: UserDefaults = .standard
    ) {
        self.stateStore = stateStore
        self.authClient = authClient
        self.userDefaults = userDefaults
        commonInit(startAuthStateTask: startAuthStateTask)
    }

    private func commonInit(startAuthStateTask: Bool) {
        loadPersistedRateLimitState()

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
                self.persistRateLimitState()
                self.logger.notice("Sign in succeeded")
            } catch {
                // Track failed attempts for rate limiting
                self.failedLoginAttempts += 1
                if self.failedLoginAttempts >= self.maxFailedAttempts {
                    self.lockoutEndTime = Date().addingTimeInterval(self.lockoutDuration)
                    self.logger.warning("Login rate limit exceeded, locked out for \(Int(self.lockoutDuration))s")
                }
                self.persistRateLimitState()

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
        guard authState != .reauthenticationRequired else {
            logger.debug("refreshSession: skipped — primary reauthentication required")
            return
        }
        guard authClient.currentSession != nil else {
            logger.debug("refreshSession: skipped — no current session (authState=\(self.authState.rawValue, privacy: .public))")
            return
        }
        if let task = refreshInFlightTask {
            logger.debug("refreshSession: awaiting in-flight refresh")
            _ = await task.value
            return
        }
        let now = Date()
        if let lastRefreshAttempt, now.timeIntervalSince(lastRefreshAttempt) < refreshCooldown {
            let remaining = Int(refreshCooldown - now.timeIntervalSince(lastRefreshAttempt))
            logger.debug("refreshSession: skipped — cooldown active (\(remaining)s remaining)")
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
        persistAuthState(accessToken: accessToken, userId: userId)
    }

    func applySession(_ session: SupabaseSessionInfo?) {
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

    func mapAuthError(_ error: Error) -> AuthAdapterError {
        if let authError = error as? AuthAdapterError {
            return authError
        }
        if let category = URLRequestErrorClassifier.category(for: error) {
            switch category {
            case .offline:
                return .networkUnavailable
            case .timeout,
                 .serverUnreachable,
                 .secureConnection,
                 .authRequired,
                 .cancelled,
                 .other:
                return .unknown(ErrorMapping.message(for: error))
            }
        }
        if error is URLError {
            return .unknown(ErrorMapping.message(for: error))
        }

        let description = error.localizedDescription.lowercased()
        if description.contains("invalid") && description.contains("credentials") {
            return .invalidCredentials
        }
        if description.contains("invalid") &&
            (description.contains("otp") ||
                description.contains("code") ||
                description.contains("token")) {
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

    func transitionToStale() {
        if authState != .staleRecoverable {
            logger.notice("Auth state transitioned to stale")
        }
        authState = .staleRecoverable
    }

    public func markSessionReauthenticationRequiredAfterAuthorizationFailure() {
        guard authState == .active else { return }
        logger.notice("Backend rejected active authorization; primary reauthentication required")
        refreshInFlightTask?.cancel()
        authState = .reauthenticationRequired
    }

    private func transitionToSignedOut(clearPersistedState: Bool) async {
        accessToken = nil
        userId = nil
        pendingVerificationEmail = nil
        lastSessionExpiryDate = nil
        refreshInFlightTask?.cancel()
        if clearPersistedState {
            do {
                flushStatePersistenceQueue()
                try clearPersistedAuthState()
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
                if authState == .active || authState == .staleRecoverable {
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
        SupabaseAuthRecovery.isAuthInvalid(error)
    }

    private func persistAuthState(accessToken: String?, userId: String?) {
        let stateStore = self.stateStore
        statePersistenceQueue.async { [weak self] in
            do {
                try stateStore.saveAccessToken(accessToken)
                try stateStore.saveUserId(userId)
            } catch {
                self?.logger.error("Failed to persist auth state: \(error.localizedDescription, privacy: .public)")
                Task { @MainActor [weak self] in
                    self?.recordError("Unable to save authentication state.")
                }
            }
        }
    }

    private func clearPersistedAuthState() throws {
        try SupabaseAuthRecovery.clearPersistedAuthState(stateStore: stateStore)
    }

    private func flushStatePersistenceQueue() {
        statePersistenceQueue.sync {}
    }
}
