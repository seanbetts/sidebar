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
        let canRefreshFromRemote = canRefreshFromRemote()
        if !force, let cached: T = cachedSnapshot(key: cacheKey) {
            apply(cached)
            if canRefreshFromRemote {
                Task {
                    await refreshIfAvailable()
                }
            }
            return true
        }
        if !force, let offline = offlineSnapshot(key: cacheKey, as: type) {
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
