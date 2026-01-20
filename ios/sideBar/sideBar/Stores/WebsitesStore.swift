import Foundation
import Combine

// MARK: - WebsitesStore

@MainActor
public final class WebsitesStore: ObservableObject {
    @Published public private(set) var items: [WebsiteItem] = []
    @Published public private(set) var active: WebsiteDetail? = nil

    private let api: any WebsitesProviding
    private let cacheClient: CacheClient
    private var isRefreshingList = false

    public init(api: any WebsitesProviding, cache: CacheClient) {
        self.api = api
        self.cacheClient = cache
    }

    public func loadList(force: Bool = false) async throws {
        try await loadWithCache(force: force)
    }

    public func loadDetail(id: String, force: Bool = false) async throws {
        let cacheKey = CacheKeys.websiteDetail(id: id)
        if !force, let cached: WebsiteDetail = cacheClient.get(key: cacheKey) {
            applyDetailUpdate(cached, persist: false)
            return
        }
        let response = try await api.get(id: id)
        applyDetailUpdate(response, persist: true)
    }

    public func updateListItem(_ item: WebsiteItem, persist: Bool = true) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
        if let active, active.id == item.id {
            let updated = updateDetail(active, with: item)
            self.active = updated
            if persist {
                cacheClient.set(key: CacheKeys.websiteDetail(id: updated.id), value: updated, ttlSeconds: CachePolicy.websiteDetail)
            }
        }
        if persist {
            persistListCache()
        }
    }

    public func insertItemAtTop(_ item: WebsiteItem, persist: Bool = true) {
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
        if let active, active.id == item.id {
            let updated = updateDetail(active, with: item)
            self.active = updated
            if persist {
                cacheClient.set(key: CacheKeys.websiteDetail(id: updated.id), value: updated, ttlSeconds: CachePolicy.websiteDetail)
            }
        }
        if persist {
            persistListCache()
        }
    }

    public func removeItem(id: String, persist: Bool = true) {
        items.removeAll { $0.id == id }
        if active?.id == id {
            active = nil
        }
        if persist {
            persistListCache()
        }
    }

    public func invalidateList() {
        cacheClient.remove(key: CacheKeys.websitesList)
    }

    public func invalidateDetail(id: String) {
        cacheClient.remove(key: CacheKeys.websiteDetail(id: id))
    }

    public func clearActive() {
        active = nil
    }

    public func reset() {
        items = []
        active = nil
    }

    public func applyRealtimeEvent(_ payload: RealtimePayload<WebsiteRealtimeRecord>) {
        switch payload.eventType {
        case .delete:
            if let websiteId = payload.oldRecord?.id ?? payload.record?.id {
                removeItem(id: websiteId, persist: true)
                cacheClient.remove(key: CacheKeys.websiteDetail(id: websiteId))
            }
        case .insert, .update:
            if let record = payload.record, let mapped = RealtimeMappers.mapWebsite(record) {
                updateListItem(mapped, persist: true)
                if let active, active.id == mapped.id {
                    let updated = updateDetail(active, with: mapped)
                    applyDetailUpdate(updated, persist: true)
                }
            }
        }
    }

    private func refreshList() async {
        guard !isRefreshingList else {
            return
        }
        isRefreshingList = true
        defer { isRefreshingList = false }
        do {
            let response = try await api.list()
            applyListUpdate(response.items, persist: true)
        } catch {
            // Ignore background refresh failures; cache remains source of truth.
        }
    }

    private func applyListUpdate(_ incoming: [WebsiteItem], persist: Bool) {
        guard shouldUpdateList(incoming) else {
            return
        }
        items = incoming
        if persist {
            persistListCache()
        }
    }

    private func shouldUpdateList(_ incoming: [WebsiteItem]) -> Bool {
        guard items.count == incoming.count else {
            return true
        }
        let existing = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        for item in incoming {
            guard let current = existing[item.id] else {
                return true
            }
            if current.updatedAt != item.updatedAt
                || current.pinned != item.pinned
                || current.pinnedOrder != item.pinnedOrder
                || current.archived != item.archived
                || current.lastOpenedAt != item.lastOpenedAt
                || current.title != item.title {
                return true
            }
        }
        return false
    }

    private func applyDetailUpdate(_ incoming: WebsiteDetail, persist: Bool) {
        guard shouldUpdateDetail(incoming) else {
            return
        }
        active = incoming
        if persist {
            cacheClient.set(key: CacheKeys.websiteDetail(id: incoming.id), value: incoming, ttlSeconds: CachePolicy.websiteDetail)
        }
    }

    private func shouldUpdateDetail(_ incoming: WebsiteDetail) -> Bool {
        guard let current = active else {
            return true
        }
        return current.updatedAt != incoming.updatedAt || current.content != incoming.content
    }

    private func persistListCache() {
        let response = WebsitesResponse(items: items)
        cacheClient.set(key: CacheKeys.websitesList, value: response, ttlSeconds: CachePolicy.websitesList)
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

extension WebsitesStore: CachedStore {
    public typealias CachedData = WebsitesResponse

    public var cache: CacheClient { cacheClient }
    public var cacheKey: String { CacheKeys.websitesList }
    public var cacheTTL: TimeInterval { CachePolicy.websitesList }

    public func fetchFromAPI() async throws -> WebsitesResponse {
        try await api.list()
    }

    public func applyData(_ data: WebsitesResponse, persist: Bool) {
        applyListUpdate(data.items, persist: persist)
    }

    public func backgroundRefresh() async {
        await refreshList()
    }
}
