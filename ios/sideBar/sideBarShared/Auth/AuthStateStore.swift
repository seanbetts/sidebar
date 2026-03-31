import Foundation

/// Defines the requirements for AuthStateStore.
public protocol AuthStateStore {
    func saveAccessToken(_ token: String?) throws
    func saveUserId(_ userId: String?) throws
    func loadAccessToken() throws -> String?
    func loadUserId() throws -> String?
    func clear() throws
}

/// Optional metadata storage for auth state that should live alongside secure session data.
public protocol AuthMetadataStore {
    func saveAuthMetadataValue(_ value: String?, forKey key: String) throws
    func loadAuthMetadataValue(forKey key: String) throws -> String?
    func removeAuthMetadataValue(forKey key: String) throws
}

/// In-memory auth state store for testing.
public nonisolated final class InMemoryAuthStateStore: AuthStateStore, @unchecked Sendable {
    private let stateLock = NSLock()
    private var accessToken: String?
    private var userId: String?

    public init() {
    }

    public func saveAccessToken(_ token: String?) throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        accessToken = token
    }

    public func saveUserId(_ userId: String?) throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        self.userId = userId
    }

    public func loadAccessToken() throws -> String? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return accessToken
    }

    public func loadUserId() throws -> String? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return userId
    }

    public func clear() throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        accessToken = nil
        userId = nil
    }
}
