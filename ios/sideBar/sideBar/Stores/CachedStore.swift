import Foundation

/// Protocol for stores with cache-first loading.
public protocol CachedStore: AnyObject {
    associatedtype CachedData: Codable

    var cache: CacheClient { get }
    var cacheKey: String { get }
    var cacheTTL: TimeInterval { get }

    func fetchFromAPI() async throws -> CachedData
    func applyData(_ data: CachedData, persist: Bool)
    func backgroundRefresh() async
}

public extension CachedStore {
    func loadWithCache(force: Bool = false) async throws {
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
