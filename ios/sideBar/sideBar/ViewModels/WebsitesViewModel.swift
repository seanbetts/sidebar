import Foundation
import Combine

// TODO: Revisit to prefer native-first data sources where applicable.

@MainActor
public final class WebsitesViewModel: ObservableObject {
    @Published public private(set) var items: [WebsiteItem] = []
    @Published public private(set) var active: WebsiteDetail? = nil
    @Published public private(set) var selectedWebsiteId: String? = nil
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var isLoadingDetail: Bool = false
    @Published public private(set) var errorMessage: String? = nil

    private let api: any WebsitesProviding
    private let cache: CacheClient

    public init(api: any WebsitesProviding, cache: CacheClient) {
        self.api = api
        self.cache = cache
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        let cached: WebsitesResponse? = cache.get(key: CacheKeys.websitesList)
        if let cached {
            items = cached.items
        }
        do {
            let response = try await api.list()
            items = response.items
            cache.set(key: CacheKeys.websitesList, value: response, ttlSeconds: CachePolicy.websitesList)
        } catch {
            if cached == nil {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    public func loadById(id: String) async {
        errorMessage = nil
        selectedWebsiteId = id
        isLoadingDetail = true
        let cacheKey = CacheKeys.websiteDetail(id: id)
        let cached: WebsiteDetail? = cache.get(key: cacheKey)
        if let cached {
            active = cached
        }
        do {
            let response = try await api.get(id: id)
            active = response
            cache.set(key: cacheKey, value: response, ttlSeconds: CachePolicy.websiteDetail)
        } catch {
            if cached == nil {
                errorMessage = error.localizedDescription
            }
        }
        isLoadingDetail = false
    }

    public func selectWebsite(id: String) async {
        await loadById(id: id)
    }

    public func clearSelection() {
        selectedWebsiteId = nil
        active = nil
    }

    public func setPinned(id: String, pinned: Bool) async {
        errorMessage = nil
        do {
            let updated = try await api.pin(id: id, pinned: pinned)
            updateListItem(updated)
            cache.remove(key: CacheKeys.websitesList)
            cache.remove(key: CacheKeys.websiteDetail(id: id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func applyRealtimeEvent(_ payload: RealtimePayload<WebsiteRealtimeRecord>) async {
        let websiteId = payload.record?.id ?? payload.oldRecord?.id
        cache.remove(key: CacheKeys.websitesList)
        if let websiteId {
            cache.remove(key: CacheKeys.websiteDetail(id: websiteId))
        }

        switch payload.eventType {
        case .delete:
            if let websiteId {
                items.removeAll { $0.id == websiteId }
                if selectedWebsiteId == websiteId {
                    selectedWebsiteId = nil
                    active = nil
                }
            }
        case .insert, .update:
            if let record = payload.record, let mapped = RealtimeMappers.mapWebsite(record) {
                updateListItem(mapped)
                if selectedWebsiteId == mapped.id {
                    await loadById(id: mapped.id)
                }
            } else {
                await load()
            }
        }
    }

    private func updateListItem(_ item: WebsiteItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
        if let active, active.id == item.id {
            self.active = updateDetail(active, with: item)
        }
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
