import Foundation
import OSLog

/// Reusable cache-first loading pattern.
public struct CachedLoader<T: Codable> {
    private let cache: CacheClient
    private let cacheKey: String
    private let ttlSeconds: TimeInterval
    private let fetch: () async throws -> T
    private let logger = Logger(subsystem: "sideBar", category: "CachedLoader")

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
    public func load(
        force: Bool = false,
        onRefresh: ((T) -> Void)? = nil
    ) async throws -> (T, Bool) {
        if !force, let cached: T = cache.get(key: cacheKey) {
            let cache = self.cache
            let fetch = self.fetch
            let cacheKey = self.cacheKey
            let ttlSeconds = self.ttlSeconds
            let logger = self.logger
            Task { [weak cache] in
                do {
                    let fresh = try await fetch()
                    guard let cache else {
                        return
                    }
                    cache.set(key: cacheKey, value: fresh, ttlSeconds: ttlSeconds)
                    if let onRefresh {
                        await MainActor.run {
                            onRefresh(fresh)
                        }
                    }
                } catch {
                    logger.error(
                        "Background refresh failed for key \(cacheKey, privacy: .public)"
                    )
                    logger.error(
                        "Background refresh error: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
            return (cached, true)
        }

        let remote = try await fetch()
        cache.set(key: cacheKey, value: remote, ttlSeconds: ttlSeconds)
        return (remote, false)
    }
}
