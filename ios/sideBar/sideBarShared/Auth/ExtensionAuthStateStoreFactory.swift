import Foundation

/// Creates the shared keychain-backed auth store used by app extensions.
public enum ExtensionAuthStateStoreFactory {
    public static func makeSharedStore() -> KeychainAuthStateStore {
        KeychainAuthStateStore(
            service: AppGroupConfiguration.keychainService,
            accessGroup: AppGroupConfiguration.keychainAccessGroup
        )
    }
}
