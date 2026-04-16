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
    let widgetDataManager: WidgetDataManager
    let offlineStore: OfflineStore?
    let networkStatus: (any NetworkStatusProviding)?
    weak var writeQueue: WriteQueue?
    weak var spotlightIndexer: (any SpotlightIndexing)?
    var isRefreshingList = false
    var isRefreshingArchived = false
    let reconciliationState: WebsitesStoreReconciliationState
    let archivedDetailRetentionDays = 7
    let archivedDetailPrefetchLimit = 50
    let archivedListLimit = 500
    let localListReconciliationWindow: TimeInterval
    var archivedListSyncedAt: String?
    var archivedSyncLoaded = false
    let archivedRefreshWaitTimeoutNanoseconds: UInt64
    let archivedRefreshPollIntervalNanoseconds: UInt64
    let persistenceQueue = DispatchQueue(
        label: "ai.sidebar.sidebar.websites-persistence",
        qos: .utility
    )

    public init(
        api: any WebsitesProviding,
        cache: CacheClient,
        widgetDataManager: WidgetDataManager = .shared,
        offlineStore: OfflineStore? = nil,
        networkStatus: (any NetworkStatusProviding)? = nil,
        localListReconciliationWindow: TimeInterval = 30,
        archivedRefreshWaitTimeoutNanoseconds: UInt64 = 10_000_000_000,
        archivedRefreshPollIntervalNanoseconds: UInt64 = 50_000_000
    ) {
        self.api = api
        self.widgetDataManager = widgetDataManager
        self.offlineStore = offlineStore
        self.networkStatus = networkStatus
        self.localListReconciliationWindow = max(0, localListReconciliationWindow)
        self.reconciliationState = WebsitesStoreReconciliationState(window: max(0, localListReconciliationWindow))
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

    var canAttemptServerRead: Bool {
        networkStatus?.offlineCapabilityPolicy.canAttemptServerRead ?? true
    }

    // MARK: - Public API

    public func loadList(force: Bool = false) async throws {
        if !force {
            let cached: WebsitesResponse? = cache.get(key: cacheKey)
            if let cached {
                updateArchivedSummary(from: cached, persist: false)
                applyListUpdate(cached.items, persist: false)
                Task { [weak self] in
                    guard let self, self.canAttemptServerRead else { return }
                    await self.refreshList()
                    await self.refreshArchivedList()
                }
                return
            }
            if let offline = offlineStore?.get(key: cacheKey, as: WebsitesResponse.self) {
                updateArchivedSummary(from: offline, persist: false)
                applyListUpdate(offline.items, persist: false)
                if canAttemptServerRead {
                    Task { [weak self] in
                        guard let self else { return }
                        await self.refreshList()
                        await self.refreshArchivedList()
                    }
                }
                return
            }
        }
        guard canAttemptServerRead else {
            throw WebsiteDetailOfflineError(message: "Websites aren't available offline yet.")
        }
        let remote = try await fetchFromAPI()
        updateArchivedSummary(from: remote, persist: true)
        applyListUpdate(remote.items, persist: true)
        cache.set(key: cacheKey, value: remote, ttlSeconds: cacheTTL)
        if canAttemptServerRead {
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
            if canAttemptServerRead {
                Task { [weak self] in
                    await self?.refreshDetail(id: id)
                }
            }
            return
        }
        if !canAttemptServerRead {
            throw offlineDetailError(for: id)
        }
        let response = try await api.get(id: id)
        applyDetailUpdate(response, persist: true)
    }

    public func loadArchivedList(force: Bool = false) async {
        guard canAttemptServerRead else { return }
        if !force, isRefreshingArchived {
            await waitForArchivedRefresh()
            return
        }
        await refreshArchivedList(force: force)
    }

    public func updateListItem(_ item: WebsiteItem, persist: Bool = true) {
        updateListItem(
            item,
            persistList: persist,
            persistDetailCache: persist,
            updateWidgets: true
        )
    }

    func updateListItem(
        _ item: WebsiteItem,
        persistList: Bool,
        persistDetailCache: Bool,
        updateWidgets: Bool
    ) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
        if let active, active.id == item.id {
            let updated = updateDetail(active, with: item)
            self.active = updated
            if persistDetailCache {
                if shouldPersistDetail(updated) {
                    persistDetail(updated)
                } else {
                    clearPersistedDetail(id: updated.id)
                }
            }
        }
        if persistList {
            persistListCache()
        }
        if updateWidgets {
            updateWidgetData(from: items)
        }
    }

    public func insertItemAtTop(_ item: WebsiteItem, persist: Bool = true) {
        preserveLocallyInsertedWebsite(id: item.id)
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
        removeItem(
            id: id,
            persistList: persist,
            clearPersistedDetailCache: true,
            updateWidgets: true
        )
    }

    func removeItem(
        id: String,
        persistList: Bool,
        clearPersistedDetailCache: Bool,
        updateWidgets: Bool
    ) {
        reconciliationState.expirations.removeValue(forKey: id)
        items.removeAll { $0.id == id }
        if active?.id == id {
            active = nil
        }
        if persistList {
            persistListCache()
        }
        if clearPersistedDetailCache {
            offlineStore?.remove(key: CacheKeys.websiteDetail(id: id))
        }
        if updateWidgets {
            updateWidgetData(from: items)
        }
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
                if mapped.deletedAt != nil {
                    removeItem(id: mapped.id, persist: true)
                    cache.remove(key: CacheKeys.websiteDetail(id: mapped.id))
                    return
                }
                let merged = mergePinnedAndArchivedFields(for: mapped, metadata: record.metadata)
                updateListItem(merged, persist: true)
                if let active, active.id == mapped.id {
                    let updated = updateDetail(active, with: merged)
                    applyDetailUpdate(updated, persist: true)
                }
            }
        }
    }

    func mergePinnedAndArchivedFields(
        for incoming: WebsiteItem,
        metadata: [String: AnyCodable]?
    ) -> WebsiteItem {
        guard let current = itemForDetail(id: incoming.id) else {
            return incoming
        }

        let hasPinned = metadata?["pinned"] != nil
        let hasPinnedOrder = metadata?["pinned_order"] != nil
        let hasArchived = metadata?["archived"] != nil

        return WebsiteItem(
            id: incoming.id,
            title: incoming.title,
            url: incoming.url,
            domain: incoming.domain,
            savedAt: incoming.savedAt,
            publishedAt: incoming.publishedAt,
            pinned: hasPinned ? incoming.pinned : current.pinned,
            pinnedOrder: hasPinnedOrder ? incoming.pinnedOrder : current.pinnedOrder,
            archived: hasArchived ? incoming.archived : current.archived,
            faviconUrl: incoming.faviconUrl,
            faviconR2Key: incoming.faviconR2Key,
            youtubeTranscripts: incoming.youtubeTranscripts ?? current.youtubeTranscripts,
            readingTime: incoming.readingTime,
            updatedAt: incoming.updatedAt,
            lastOpenedAt: incoming.lastOpenedAt,
            deletedAt: incoming.deletedAt
        )
    }

}
