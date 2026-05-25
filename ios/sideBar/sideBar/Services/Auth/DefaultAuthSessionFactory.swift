import Foundation
@preconcurrency import sideBarShared

/// Builds the product-facing auth session used by app composition.
@MainActor public protocol AuthSessionFactory {
    func makeAuthSession(
        config: EnvironmentConfig,
        useInMemoryStateStore: Bool,
        startAuthStateTask: Bool
    ) -> AuthSession
}

/// Production auth factory that hides provider-specific session construction.
@MainActor public struct DefaultAuthSessionFactory: AuthSessionFactory {
    public init() {
    }

    public func makeAuthSession(
        config: EnvironmentConfig,
        useInMemoryStateStore: Bool,
        startAuthStateTask: Bool
    ) -> AuthSession {
        let stateStore = makeStateStore(useInMemoryStateStore: useInMemoryStateStore)
        return SupabaseAuthAdapter(
            config: config,
            stateStore: stateStore,
            startAuthStateTask: startAuthStateTask
        )
    }

    private func makeStateStore(useInMemoryStateStore: Bool) -> AuthStateStore {
        if useInMemoryStateStore {
            return InMemoryAuthStateStore()
        }
        return KeychainAuthStateStore(
            service: AppGroupConfiguration.keychainService,
            accessGroup: AppGroupConfiguration.keychainAccessGroup
        )
    }
}
