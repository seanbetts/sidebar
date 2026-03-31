import Foundation

/// Creates the shared keychain-backed auth store used by app extensions.
public enum ExtensionAuthStateStoreFactory {
    public static func makeSharedStore() -> KeychainAuthStateStore {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return sharedTestStore
        }
        return KeychainAuthStateStore(
            service: AppGroupConfiguration.keychainService,
            accessGroup: AppGroupConfiguration.keychainAccessGroup
        )
    }

    private static let sharedTestStore = KeychainAuthStateStore(
        service: AppGroupConfiguration.keychainService,
        accessGroup: AppGroupConfiguration.keychainAccessGroup,
        useInMemoryStore: true
    )
}
