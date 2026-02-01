import Foundation
import Supabase
import sideBarShared

/// Bridges KeychainAuthStateStore to Supabase's AuthLocalStorage protocol.
///
/// This adapter allows Supabase to use our Keychain storage for session persistence,
/// eliminating the race condition between Supabase's internal storage and our separate
/// Keychain storage. With unified storage, Supabase will automatically load sessions
/// from our Keychain on cold launch.
///
/// Marked as `@unchecked Sendable` because KeychainAuthStateStore uses the Security
/// framework's Keychain APIs, which are thread-safe.
public final class SupabaseKeychainStorage: AuthLocalStorage, @unchecked Sendable {
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
