import Foundation

/// Reusable cache-first loading pattern.
public struct CachedLoader<T: Codable> {
    private let cache: CacheClient
    private let cacheKey: String
    private let ttlSeconds: TimeInterval
    private let fetch: () async throws -> T

    public init(
        cache: CacheClient,
        key: String,
        ttl: TimeInterval,
        fetch: @escaping () async throws -> T
    ) {
        self.cache = cache
        self.cacheKey = key
        self.ttlSeconds = ttl
        self.fetch = fetch
    }

    /// Load with cache-first strategy.
    /// - Returns: Tuple of (data, wasFromCache)
    public func load(force: Bool = false) async throws -> (T, Bool) {
        if !force, let cached: T = cache.get(key: cacheKey) {
            Task {
                if let fresh = try? await fetch() {
                    cache.set(key: cacheKey, value: fresh, ttlSeconds: ttlSeconds)
                }
            }
            return (cached, true)
        }

        let remote = try await fetch()
        cache.set(key: cacheKey, value: remote, ttlSeconds: ttlSeconds)
        return (remote, false)
    }
}
