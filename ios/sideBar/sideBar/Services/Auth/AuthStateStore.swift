import Foundation

public protocol AuthStateStore {
    func saveAccessToken(_ token: String?) throws
    func saveUserId(_ userId: String?) throws
    func loadAccessToken() throws -> String?
    func loadUserId() throws -> String?
    func clear() throws
}

public final class InMemoryAuthStateStore: AuthStateStore {
    private var accessToken: String?
    private var userId: String?

    public init() {
    }

    public func saveAccessToken(_ token: String?) throws {
        accessToken = token
    }

    public func saveUserId(_ userId: String?) throws {
        self.userId = userId
    }

    public func loadAccessToken() throws -> String? {
        accessToken
    }

    public func loadUserId() throws -> String? {
        userId
    }

    public func clear() throws {
        accessToken = nil
        userId = nil
    }
}
