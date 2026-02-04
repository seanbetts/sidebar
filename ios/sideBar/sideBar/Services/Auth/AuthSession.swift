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
public protocol AuthSession {
    var accessToken: String? { get }
    /// Token to use for Authorization headers (nil when auth is stale/signed out).
    var authorizationToken: String? { get }
    var userId: String? { get }
    var authState: AuthState { get }
    func signIn(email: String, password: String) async throws
    func refreshSession() async
    func refreshSessionIfStale() async
    func signOut() async
}

/// No-op auth session placeholder.
public final class PlaceholderAuthSession: AuthSession {
    public private(set) var accessToken: String?
    public private(set) var userId: String?
    public private(set) var authState: AuthState = .signedOut

    public var authorizationToken: String? {
        authState == .active ? accessToken : nil
    }

    public init() {
    }

    public func signIn(email: String, password: String) async throws {
        _ = email
        _ = password
        authState = .active
    }

    public func refreshSession() async {
    }

    public func refreshSessionIfStale() async {
    }

    public func signOut() async {
        accessToken = nil
        userId = nil
        authState = .signedOut
    }
}
