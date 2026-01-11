import Foundation

@MainActor
public final class WebsitesStore: ObservableObject {
    @Published public private(set) var items: [WebsiteItem] = []
    @Published public private(set) var active: WebsiteDetail? = nil

    private let api: any WebsitesProviding
    private let cache: CacheClient

    public init(api: any WebsitesProviding, cache: CacheClient) {
        self.api = api
        self.cache = cache
    }

    public func loadList(force: Bool = false) async throws {
        if !force, let cached: WebsitesResponse = cache.get(key: CacheKeys.websitesList) {
            items = cached.items
            return
        }
        let response = try await api.list()
        items = response.items
        cache.set(key: CacheKeys.websitesList, value: response, ttlSeconds: CachePolicy.websitesList)
    }

    public func loadDetail(id: String, force: Bool = false) async throws {
        let cacheKey = CacheKeys.websiteDetail(id: id)
        if !force, let cached: WebsiteDetail = cache.get(key: cacheKey) {
            active = cached
            return
        }
        let response = try await api.get(id: id)
        active = response
        cache.set(key: cacheKey, value: response, ttlSeconds: CachePolicy.websiteDetail)
    }

    public func updateListItem(_ item: WebsiteItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
        if let active, active.id == item.id {
            self.active = updateDetail(active, with: item)
        }
    }

    public func removeItem(id: String) {
        items.removeAll { $0.id == id }
        if active?.id == id {
            active = nil
        }
    }

    public func invalidateList() {
        cache.remove(key: CacheKeys.websitesList)
    }

    public func invalidateDetail(id: String) {
        cache.remove(key: CacheKeys.websiteDetail(id: id))
    }

    public func clearActive() {
        active = nil
    }

    public func reset() {
        items = []
        active = nil
    }

    private func updateDetail(_ detail: WebsiteDetail, with item: WebsiteItem) -> WebsiteDetail {
        WebsiteDetail(
            id: detail.id,
            title: item.title,
            url: item.url,
            urlFull: detail.urlFull,
            domain: item.domain,
            content: detail.content,
            source: detail.source,
            savedAt: item.savedAt ?? detail.savedAt,
            publishedAt: item.publishedAt ?? detail.publishedAt,
            pinned: item.pinned,
            pinnedOrder: item.pinnedOrder,
            archived: item.archived,
            youtubeTranscripts: detail.youtubeTranscripts ?? item.youtubeTranscripts,
            updatedAt: item.updatedAt ?? detail.updatedAt,
            lastOpenedAt: item.lastOpenedAt ?? detail.lastOpenedAt
        )
    }
}
