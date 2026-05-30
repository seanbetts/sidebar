import Foundation

/// Persists optimistic onboarding state used before remote onboarding refresh completes.
@MainActor public final class OnboardingLocalStateStore {
    private let cache: CacheClient

    public init(cache: CacheClient) {
        self.cache = cache
    }

    public func load() -> OnboardingState? {
        cache.get(key: CacheKeys.onboardingState)
    }

    public func save(_ state: OnboardingState) {
        cache.set(
            key: CacheKeys.onboardingState,
            value: state,
            ttlSeconds: CachePolicy.onboardingState
        )
    }

    public func clear() {
        cache.remove(key: CacheKeys.onboardingState)
    }
}
