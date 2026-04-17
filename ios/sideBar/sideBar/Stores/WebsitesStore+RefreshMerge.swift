import Foundation

extension WebsitesStore {
    func syncActiveDetail(with items: [WebsiteItem], persist: Bool) {
        guard let active,
              let item = items.first(where: { $0.id == active.id }) else {
            return
        }
        let updated = updateDetail(active, with: item)
        guard shouldSyncDetailMetadata(current: active, updated: updated) else {
            return
        }
        self.active = updated
        guard persist else {
            return
        }
        if shouldPersistDetail(updated) {
            persistDetail(updated)
        } else {
            clearPersistedDetail(id: updated.id)
        }
    }

    func shouldSyncDetailMetadata(current: WebsiteDetail, updated: WebsiteDetail) -> Bool {
        current.title != updated.title
            || current.url != updated.url
            || current.domain != updated.domain
            || current.savedAt != updated.savedAt
            || current.publishedAt != updated.publishedAt
            || current.pinned != updated.pinned
            || current.pinnedOrder != updated.pinnedOrder
            || current.archived != updated.archived
            || current.faviconUrl != updated.faviconUrl
            || current.faviconR2Key != updated.faviconR2Key
            || current.youtubeTranscripts != updated.youtubeTranscripts
            || current.readingTime != updated.readingTime
            || current.updatedAt != updated.updatedAt
            || current.lastOpenedAt != updated.lastOpenedAt
    }
}
