import Foundation

extension WebsitesStore {
    func pinnedWebsiteOrder() -> [String] {
        items
            .filter { $0.pinned && !$0.archived }
            .sorted(by: sortPinnedWebsites)
            .map(\.id)
    }

    func applyPinnedOrder(_ ids: [String]) {
        guard !items.isEmpty else { return }

        let pinnedOrderLookup = ids.enumerated().reduce(into: [String: Int]()) { result, pair in
            result[pair.element] = pair.offset
        }

        items = items.map { item in
            guard item.pinned, let pinnedOrder = pinnedOrderLookup[item.id] else {
                return item
            }
            return WebsiteItem(
                id: item.id,
                title: item.title,
                url: item.url,
                domain: item.domain,
                savedAt: item.savedAt,
                publishedAt: item.publishedAt,
                pinned: item.pinned,
                pinnedOrder: pinnedOrder,
                archived: item.archived,
                faviconUrl: item.faviconUrl,
                faviconR2Key: item.faviconR2Key,
                youtubeTranscripts: item.youtubeTranscripts,
                readingTime: item.readingTime,
                updatedAt: item.updatedAt,
                lastOpenedAt: item.lastOpenedAt,
                deletedAt: item.deletedAt
            )
        }
        updateWidgetData(from: items)
        persistListCache()
    }

    private func sortPinnedWebsites(_ lhs: WebsiteItem, _ rhs: WebsiteItem) -> Bool {
        let leftOrder = lhs.pinnedOrder ?? Int.max
        let rightOrder = rhs.pinnedOrder ?? Int.max
        if leftOrder != rightOrder {
            return leftOrder < rightOrder
        }
        return lhs.id < rhs.id
    }
}
