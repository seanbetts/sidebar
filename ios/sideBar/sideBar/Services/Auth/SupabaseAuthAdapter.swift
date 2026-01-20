import Foundation
import Combine
import Supabase
import os

public struct AuthErrorEvent: Equatable {
    public let id = UUID()
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

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
public final class SupabaseAuthAdapter: ObservableObject, AuthSession {
    @Published public private(set) var accessToken: String?
    @Published public private(set) var userId: String?
    @Published public private(set) var authError: AuthErrorEvent?
    @Published public private(set) var sessionExpiryWarning: Date?

    private let stateStore: AuthStateStore
    private let supabase: SupabaseClient
    private var authStateTask: Task<Void, Never>?
    private var refreshScheduleTask: Task<Void, Never>?
    private var refreshInFlightTask: Task<Void, Never>?
    private var warningTask: Task<Void, Never>?
    private var signInTask: Task<Void, Error>?
    private let logger = Logger(subsystem: "sideBar", category: "Auth")
    private let sessionWarningLeadTime: TimeInterval = 300
    private let refreshCooldown: TimeInterval = 60
    private let offlineAccessWindow: TimeInterval = 60 * 60 * 24
    private let lastAuthTimestampKey = AppStorageKeys.lastAuthTimestamp
    private var lastSessionExpiryDate: Date?
    private var lastRefreshAttempt: Date?
    private var sessionWarningToken = UUID()

    public init(config: EnvironmentConfig, stateStore: AuthStateStore) {
        self.stateStore = stateStore

        let authOptions = SupabaseClientOptions.AuthOptions(
            emitLocalSessionAsInitialSession: true
        )
        supabase = SupabaseClient(
            supabaseURL: config.supabaseUrl,
            supabaseKey: config.supabaseAnonKey,
            options: SupabaseClientOptions(auth: authOptions)
        )

        if let session = supabase.auth.currentSession {
            applySession(session)
        } else {
            do {
                let storedToken = try stateStore.loadAccessToken()
                let storedUserId = try stateStore.loadUserId()
                if storedToken != nil, storedUserId != nil, shouldAllowOfflineAccess(hasStoredToken: true) {
                    accessToken = storedToken
                    userId = storedUserId
                } else {
                    do {
                        try stateStore.clear()
                    } catch {
                        logger.error("Failed to clear auth state: \(error.localizedDescription, privacy: .public)")
                    }
                }
            } catch {
                recordError("Unable to restore authentication state.")
            }
        }

        authStateTask = Task { [supabase, weak self] in
            for await (_, session) in supabase.auth.authStateChanges {
                guard let self else { return }
                self.applySession(session)
            }
        }
    }

    deinit {
        authStateTask?.cancel()
        refreshScheduleTask?.cancel()
        refreshInFlightTask?.cancel()
        warningTask?.cancel()
    }

    public func signIn(email: String, password: String) async throws {
        guard signInTask == nil else {
            throw AuthAdapterError.signInInProgress
        }
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.supabase.auth.signIn(email: email, password: password)
                if let session = self.supabase.auth.currentSession {
                    self.applySession(session)
                }
                self.logger.notice("Sign in succeeded")
            } catch {
                let mappedError = self.mapAuthError(error)
                self.logger.error("Sign in failed: \(mappedError.localizedDescription, privacy: .public)")
                throw mappedError
            }
        }
        signInTask = task
        defer { signInTask = nil }
        try await task.value
    }

    public func refreshSession() async {
        guard accessToken != nil, userId != nil, supabase.auth.currentSession != nil else {
            sessionExpiryWarning = nil
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
                let session = try await self.supabase.auth.refreshSession()
                self.applySession(session)
                self.logger.notice("Session refresh succeeded")
            } catch {
                self.logger.error("Session refresh failed: \(error.localizedDescription, privacy: .public)")
                if let expiryDate = self.lastSessionExpiryDate,
                   expiryDate.timeIntervalSinceNow <= self.sessionWarningLeadTime {
                    self.sessionExpiryWarning = expiryDate
                }
                self.recordError(AuthAdapterError.sessionRefreshFailed.errorDescription ?? "Session refresh failed.")
            }
        }
        refreshInFlightTask = task
        defer { refreshInFlightTask = nil }
        _ = await task.value
    }

    public func signOut() async {
        do {
            try await supabase.auth.signOut()
        } catch {
            // Best effort: clear local auth even if server sign-out fails.
        }
        accessToken = nil
        userId = nil
        do {
            try stateStore.clear()
        } catch {
            logger.error("Failed to clear auth state: \(error.localizedDescription, privacy: .public)")
        }
        sessionExpiryWarning = nil
        lastSessionExpiryDate = nil
        warningTask?.cancel()
        refreshScheduleTask?.cancel()
        refreshInFlightTask?.cancel()
        sessionWarningToken = UUID()
        logger.notice("Signed out")
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

    private func applySession(_ session: Session?) {
        guard let session else {
            restoreSession(accessToken: nil, userId: nil)
            sessionExpiryWarning = nil
            lastSessionExpiryDate = nil
            warningTask?.cancel()
            refreshScheduleTask?.cancel()
            refreshInFlightTask?.cancel()
            return
        }

        let resolvedExpiry = Self.sessionExpiryDate(from: session)
        if resolvedExpiry <= Date() {
            Task { await refreshSession() }
            return
        }

        restoreSession(accessToken: session.accessToken, userId: session.user.id.uuidString)
        updateLastAuthTimestamp(Date())
        scheduleSessionManagement(for: session, expiresAt: resolvedExpiry)
    }

    private func scheduleSessionManagement(for session: Session, expiresAt: Date) {
        warningTask?.cancel()
        refreshScheduleTask?.cancel()
        sessionExpiryWarning = nil
        sessionWarningToken = UUID()
        let warningToken = sessionWarningToken

        let now = Date()
        if expiresAt <= now {
            Task { await refreshSession() }
            return
        }
        lastSessionExpiryDate = expiresAt
        let warningDelay = expiresAt.addingTimeInterval(-sessionWarningLeadTime).timeIntervalSinceNow
        if warningDelay > 5 {
            warningTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(warningDelay))
                } catch {
                    if !Task.isCancelled {
                        self?.logger.error("Session warning sleep failed: \(error.localizedDescription, privacy: .public)")
                    }
                    return
                }
                await MainActor.run {
                    guard let self, self.sessionWarningToken == warningToken else { return }
                    self.sessionExpiryWarning = expiresAt
                }
            }
        }

        let refreshDelay = max(warningDelay, 0)
        if refreshDelay > 0 {
            refreshScheduleTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(refreshDelay))
                } catch {
                    if !Task.isCancelled {
                        self?.logger.error("Session refresh sleep failed: \(error.localizedDescription, privacy: .public)")
                    }
                    return
                }
                await self?.refreshSession()
            }
        } else {
            Task { await refreshSession() }
        }
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

    static func sessionExpiryDate(from session: Session) -> Date {
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
}
