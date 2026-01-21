import Foundation

/// Base class for stores with cache-first loading.
/// Subclasses must override `cacheKey`, `cacheTTL`, `fetchFromAPI()`, `applyData()`, and `backgroundRefresh()`.
@MainActor
open class CachedStoreBase<CachedData: Codable>: ObservableObject {
    public let cache: CacheClient

    open var cacheKey: String {
        fatalError("Subclass must override cacheKey")
    }

    open var cacheTTL: TimeInterval {
        fatalError("Subclass must override cacheTTL")
    }

    public init(cache: CacheClient) {
        self.cache = cache
    }

    open func fetchFromAPI() async throws -> CachedData {
        fatalError("Subclass must override fetchFromAPI()")
    }

    open func applyData(_ data: CachedData, persist: Bool) {
        fatalError("Subclass must override applyData(_:persist:)")
    }

    open func backgroundRefresh() async {
        fatalError("Subclass must override backgroundRefresh()")
    }

    public func loadWithCache(force: Bool = false) async throws {
        let cached: CachedData? = force ? nil : cache.get(key: cacheKey)

        if let cached {
            applyData(cached, persist: false)
            Task { [weak self] in
                await self?.backgroundRefresh()
            }
            return
        }

        let remote = try await fetchFromAPI()
        applyData(remote, persist: true)
        cache.set(key: cacheKey, value: remote, ttlSeconds: cacheTTL)
    }
}
