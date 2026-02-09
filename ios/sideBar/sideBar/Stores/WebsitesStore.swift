import Foundation
import Combine
import sideBarShared

// MARK: - WebsitesStore

/// Persistent store for saved websites list and active website detail.
///
/// Manages the list of saved websites and the currently selected website's full content.
/// Uses `CachedStoreBase` for cache-first loading with background refresh.
///
/// ## Responsibilities
/// - Load and cache the saved websites list
/// - Load and cache individual website details with content
/// - Update list items in-place for pin/archive/rename operations
/// - Handle real-time website events (insert, update, delete)
public final class WebsitesStore: CachedStoreBase<WebsitesResponse> {
    @Published public internal(set) var items: [WebsiteItem] = []
    @Published public internal(set) var active: WebsiteDetail?
    @Published public internal(set) var archivedSummary: ArchivedSummary?

    let api: any WebsitesProviding
    let offlineStore: OfflineStore?
    let networkStatus: (any NetworkStatusProviding)?
    weak var writeQueue: WriteQueue?
    weak var spotlightIndexer: (any SpotlightIndexing)?
    var isRefreshingList = false
    var isRefreshingArchived = false
    let archivedDetailRetentionDays = 7
    let archivedDetailPrefetchLimit = 50
    let archivedListLimit = 500
    var archivedListSyncedAt: String?
    var archivedSyncLoaded = false
    let archivedRefreshWaitTimeoutNanoseconds: UInt64
    let archivedRefreshPollIntervalNanoseconds: UInt64

    public init(
        api: any WebsitesProviding,
        cache: CacheClient,
        offlineStore: OfflineStore? = nil,
        networkStatus: (any NetworkStatusProviding)? = nil,
        archivedRefreshWaitTimeoutNanoseconds: UInt64 = 10_000_000_000,
        archivedRefreshPollIntervalNanoseconds: UInt64 = 50_000_000
    ) {
        self.api = api
        self.offlineStore = offlineStore
        self.networkStatus = networkStatus
        let pollInterval = max(1, archivedRefreshPollIntervalNanoseconds)
        self.archivedRefreshPollIntervalNanoseconds = pollInterval
        self.archivedRefreshWaitTimeoutNanoseconds = max(pollInterval, archivedRefreshWaitTimeoutNanoseconds)
        super.init(cache: cache)
    }

    // MARK: - CachedStoreBase Overrides

    public override var cacheKey: String { CacheKeys.websitesList }
    public override var cacheTTL: TimeInterval { CachePolicy.websitesList }

    public override func fetchFromAPI() async throws -> WebsitesResponse {
        try await api.list()
    }

    public override func applyData(_ data: WebsitesResponse, persist: Bool) {
        updateArchivedSummary(from: data, persist: persist)
        applyListUpdate(data.items, persist: persist)
    }

    public override func backgroundRefresh() async {
        await refreshList()
        await refreshArchivedList()
    }

    // MARK: - Public API

    public func loadList(force: Bool = false) async throws {
        if !force {
            let cached: WebsitesResponse? = cache.get(key: cacheKey)
            if let cached {
                updateArchivedSummary(from: cached, persist: false)
                applyListUpdate(cached.items, persist: false)
                Task { [weak self] in
                    await self?.refreshList()
                    await self?.refreshArchivedList()
                }
                return
            }
            if let offline = offlineStore?.get(key: cacheKey, as: WebsitesResponse.self) {
                updateArchivedSummary(from: offline, persist: false)
                applyListUpdate(offline.items, persist: false)
                if !(networkStatus?.isOffline ?? false) {
                    Task { [weak self] in
                        await self?.refreshList()
                        await self?.refreshArchivedList()
                    }
                }
                return
            }
        }
        let remote = try await fetchFromAPI()
        updateArchivedSummary(from: remote, persist: true)
        applyListUpdate(remote.items, persist: true)
        cache.set(key: cacheKey, value: remote, ttlSeconds: cacheTTL)
        if !(networkStatus?.isOffline ?? false) {
            Task { [weak self] in
                await self?.refreshArchivedList()
            }
        }
    }

    public func loadDetail(id: String, force: Bool = false) async throws {
        let cacheKey = CacheKeys.websiteDetail(id: id)
        if !force, let cached: WebsiteDetail = cache.get(key: cacheKey) {
            applyDetailUpdate(cached, persist: false)
            return
        }
        if !force, let offline = offlineStore?.get(key: cacheKey, as: WebsiteDetail.self) {
            applyDetailUpdate(offline, persist: false)
            if !(networkStatus?.isOffline ?? false) {
                Task { [weak self] in
                    await self?.refreshDetail(id: id)
                }
            }
            return
        }
        if networkStatus?.isOffline ?? false {
            throw offlineDetailError(for: id)
        }
        let response = try await api.get(id: id)
        applyDetailUpdate(response, persist: true)
    }

    public func loadArchivedList(force: Bool = false) async {
        guard !(networkStatus?.isOffline ?? false) else { return }
        if !force, isRefreshingArchived {
            await waitForArchivedRefresh()
            return
        }
        await refreshArchivedList(force: force)
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
                if shouldPersistDetail(updated) {
                    persistDetail(updated)
                } else {
                    clearPersistedDetail(id: updated.id)
                }
            }
        }
        if persist {
            persistListCache()
        }
        updateWidgetData(from: items)
    }

    public func insertItemAtTop(_ item: WebsiteItem, persist: Bool = true) {
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
        if let active, active.id == item.id {
            let updated = updateDetail(active, with: item)
            self.active = updated
            if persist {
                if shouldPersistDetail(updated) {
                    persistDetail(updated)
                } else {
                    clearPersistedDetail(id: updated.id)
                }
            }
        }
        if persist {
            persistListCache()
        }
        updateWidgetData(from: items)
    }

    public func removeItem(id: String, persist: Bool = true) {
        items.removeAll { $0.id == id }
        if active?.id == id {
            active = nil
        }
        if persist {
            persistListCache()
        }
        offlineStore?.remove(key: CacheKeys.websiteDetail(id: id))
        updateWidgetData(from: items)
        removeWebsiteFromSpotlight(id: id)
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
        archivedSummary = nil
        archivedListSyncedAt = nil
        archivedSyncLoaded = false
    }

    public func attachWriteQueue(_ writeQueue: WriteQueue) {
        self.writeQueue = writeQueue
    }

    public func loadFromOffline() async {
        guard let offline = offlineStore?.get(key: cacheKey, as: WebsitesResponse.self) else { return }
        updateArchivedSummary(from: offline, persist: false)
        applyListUpdate(offline.items, persist: false)
    }

    public func saveOfflineSnapshot() async {
        persistListCache()
        if let active, shouldPersistDetail(active) {
            let key = CacheKeys.websiteDetail(id: active.id)
            let lastSyncAt = offlineStore?.lastSyncAt(for: key)
            offlineStore?.set(key: key, entityType: "website", value: active, lastSyncAt: lastSyncAt)
        } else if let active {
            clearPersistedDetail(id: active.id)
        }
    }

    public func applyRealtimeEvent(_ payload: RealtimePayload<WebsiteRealtimeRecord>) {
        switch payload.eventType {
        case .delete:
            if let websiteId = payload.oldRecord?.id ?? payload.record?.id {
                removeItem(id: websiteId, persist: true)
                cache.remove(key: CacheKeys.websiteDetail(id: websiteId))
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

}
