import Foundation
import Supabase

public final class SupabaseKeychainStorageBridge: AuthLocalStorage, @unchecked Sendable {
    private let stateStore: KeychainAuthStateStore

    public init(stateStore: KeychainAuthStateStore) {
        self.stateStore = stateStore
    }

    public func store(key: String, value: Data) throws {
        try stateStore.saveSessionData(value, forKey: key)
    }

    public func retrieve(key: String) throws -> Data? {
        try stateStore.loadSessionData(forKey: key)
    }

    public func remove(key: String) throws {
        try stateStore.removeSessionData(forKey: key)
    }
}
