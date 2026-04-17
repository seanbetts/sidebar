import Foundation

extension WebsitesStore {
    func hydrateListFromCache() {
        if let cached: WebsitesResponse = cache.get(key: cacheKey) {
            updateArchivedSummary(from: cached, persist: false)
            applyListUpdate(cached.items, persist: false)
            return
        }
        if let offline = offlineStore?.get(key: cacheKey, as: WebsitesResponse.self) {
            updateArchivedSummary(from: offline, persist: false)
            applyListUpdate(offline.items, persist: false)
        }
    }
}
