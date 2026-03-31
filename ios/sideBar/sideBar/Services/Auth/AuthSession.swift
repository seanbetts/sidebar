import Foundation
import Combine

/// High-level authentication state.
public enum AuthState: String, Equatable, Sendable {
    /// No recoverable session; user must sign in.
    case signedOut
    /// Session is usable for network requests and sync.
    case active
    /// App can remain usable locally, but network auth/sync is paused until refresh succeeds.
    case stale
}

/// Defines the requirements for AuthSession.
public protocol AuthSession: AnyObject {
    var accessToken: String? { get }
    /// Token to use for Authorization headers (nil when auth is stale/signed out).
    var authorizationToken: String? { get }
    var userId: String? { get }
    var authState: AuthState { get }
    var pendingVerificationEmail: String? { get }
    func signIn(email: String, password: String) async throws
    func signUp(email: String, password: String) async throws
    func verifyOTP(email: String, code: String) async throws
    func refreshSession() async
    func refreshSessionIfStale() async
    func signOut() async
}

/// No-op auth session placeholder.
public final class PlaceholderAuthSession: AuthSession {
    public private(set) var accessToken: String?
    public private(set) var userId: String?
    public private(set) var authState: AuthState

    public var authorizationToken: String? {
        authState == .active ? accessToken : nil
    }

    public var pendingVerificationEmail: String? {
        nil
    }

    public init(
        accessToken: String? = nil,
        userId: String? = nil,
        authState: AuthState = .signedOut
    ) {
        self.accessToken = accessToken
        self.userId = userId
        self.authState = authState
    }

    public func signIn(email: String, password: String) async throws {
        _ = email
        _ = password
        authState = .active
    }

    public func signUp(email: String, password: String) async throws {
        _ = email
        _ = password
    }

    public func verifyOTP(email: String, code: String) async throws {
        _ = email
        _ = code
    }

    public func refreshSession() async {
        guard accessToken != nil, userId != nil else { return }
        authState = .active
    }

    public func refreshSessionIfStale() async {
    }

    public func signOut() async {
        accessToken = nil
        userId = nil
        authState = .signedOut
    }
}
