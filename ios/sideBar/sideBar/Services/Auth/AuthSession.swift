import Foundation
import Combine

public protocol AuthSession {
    var accessToken: String? { get }
    var userId: String? { get }
    func signIn(email: String, password: String) async throws
    func refreshSession() async
    func signOut() async
}

/// No-op auth session placeholder.
public final class PlaceholderAuthSession: AuthSession {
    public private(set) var accessToken: String?
    public private(set) var userId: String?

    public init() {
    }

    public func signIn(email: String, password: String) async throws {
        _ = email
        _ = password
    }

    public func refreshSession() async {
    }

    public func signOut() async {
        accessToken = nil
        userId = nil
    }
}
