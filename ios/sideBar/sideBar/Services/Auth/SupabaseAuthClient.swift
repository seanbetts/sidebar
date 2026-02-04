import Foundation
import Supabase

/// Small testable wrapper around Supabase Auth.
///
/// This avoids coupling auth state logic to Supabase SDK types in unit tests.
public struct SupabaseSessionInfo: Equatable, Sendable {
    public let accessToken: String
    public let userId: String
    public let expiresAt: TimeInterval

    public init(accessToken: String, userId: String, expiresAt: TimeInterval) {
        self.accessToken = accessToken
        self.userId = userId
        self.expiresAt = expiresAt
    }
}

/// Simplified auth events used by the app's auth state machine.
public enum SupabaseAuthEvent: Equatable, Sendable {
    case initialSession
    case signedOut
    case other(String)
}

/// Minimal interface for the parts of Supabase Auth used by the app.
///
/// This protocol exists to make `SupabaseAuthAdapter` unit-testable.
public protocol SupabaseAuthClientProtocol: Sendable {
    var currentSession: SupabaseSessionInfo? { get }
    var authStateChanges: AsyncStream<(SupabaseAuthEvent, SupabaseSessionInfo?)> { get }
    func signIn(email: String, password: String) async throws
    func refreshSession() async throws -> SupabaseSessionInfo
    func signOut() async throws
}

/// Production wrapper around `SupabaseClient.auth` that conforms to `SupabaseAuthClientProtocol`.
public final class SupabaseAuthClient: SupabaseAuthClientProtocol {
    private let supabase: SupabaseClient

    public init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    public var currentSession: SupabaseSessionInfo? {
        guard let session = supabase.auth.currentSession else { return nil }
        return Self.mapSession(session)
    }

    public var authStateChanges: AsyncStream<(SupabaseAuthEvent, SupabaseSessionInfo?)> {
        AsyncStream { continuation in
            let task = Task { [supabase] in
                for await (event, session) in supabase.auth.authStateChanges {
                    continuation.yield((Self.mapEvent(event), session.map(Self.mapSession)))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func signIn(email: String, password: String) async throws {
        try await supabase.auth.signIn(email: email, password: password)
    }

    public func refreshSession() async throws -> SupabaseSessionInfo {
        let session = try await supabase.auth.refreshSession()
        return Self.mapSession(session)
    }

    public func signOut() async throws {
        try await supabase.auth.signOut()
    }

    private static func mapSession(_ session: Session) -> SupabaseSessionInfo {
        SupabaseSessionInfo(
            accessToken: session.accessToken,
            userId: session.user.id.uuidString,
            expiresAt: session.expiresAt
        )
    }

    private static func mapEvent<T>(_ event: T) -> SupabaseAuthEvent {
        let description = String(describing: event).uppercased()
        if description.contains("INITIAL_SESSION") || description == "INITIALSESSION" || description == "INITIAL_SESSION" {
            return .initialSession
        }
        if description.contains("SIGNED_OUT") || description == "SIGNEDOUT" || description == "SIGNED_OUT" {
            return .signedOut
        }
        return .other(description)
    }
}
