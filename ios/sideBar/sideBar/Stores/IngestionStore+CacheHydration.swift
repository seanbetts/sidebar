import Foundation

extension IngestionStore {
    func hydrateListFromCache() {
        if let cached: IngestionListResponse = cache.get(key: cacheKey) {
            applyListUpdate(cached.items, persist: false)
            return
        }
        if let offline = offlineStore?.get(key: cacheKey, as: IngestionListResponse.self) {
            applyListUpdate(offline.items, persist: false)
        }
    }
}
