import Foundation
import sideBarShared

extension WebsitesStore {
    func maintainPersistedDetailAsync(_ detail: WebsiteDetail) {
        if shouldPersistDetail(detail) {
            persistDetailAsync(detail)
        } else {
            clearPersistedDetailAsync(id: detail.id)
        }
    }

    private func persistDetailAsync(_ detail: WebsiteDetail) {
        let cache = self.cache
        let offlineStore = self.offlineStore
        let lastSyncAt = Date()
        persistenceQueue.async {
            cache.set(
                key: CacheKeys.websiteDetail(id: detail.id),
                value: detail,
                ttlSeconds: CachePolicy.websiteDetail
            )
            offlineStore?.set(
                key: CacheKeys.websiteDetail(id: detail.id),
                entityType: "website",
                value: detail,
                lastSyncAt: lastSyncAt
            )
        }
    }

    private func clearPersistedDetailAsync(id: String) {
        let cache = self.cache
        let offlineStore = self.offlineStore
        persistenceQueue.async {
            cache.remove(key: CacheKeys.websiteDetail(id: id))
            offlineStore?.remove(key: CacheKeys.websiteDetail(id: id))
        }
    }
}
