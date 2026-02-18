import Foundation

extension TasksStore {
    @discardableResult
    func applyCachedOrOffline<T: Codable>(
        force: Bool,
        cacheKey: String,
        type: T.Type,
        apply: (T) -> Void,
        refreshIfAvailable: @escaping @MainActor () async -> Void
    ) -> Bool {
        let canRefreshFromRemote = (networkStatus?.isNetworkAvailable ?? true)
            && (networkStatus?.isServerReachable ?? true)
        if !force, let cached: T = cache.get(key: cacheKey) {
            apply(cached)
            if canRefreshFromRemote {
                Task {
                    await refreshIfAvailable()
                }
            }
            return true
        }
        if !force, let offline = offlineStore?.get(key: cacheKey, as: type) {
            apply(offline)
            if canRefreshFromRemote {
                Task {
                    await refreshIfAvailable()
                }
            }
            return true
        }
        return false
    }
}
