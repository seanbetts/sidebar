import Foundation
import Combine
#if canImport(WidgetKit)
import WidgetKit
#endif

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
    @Published public private(set) var items: [WebsiteItem] = []
    @Published public private(set) var active: WebsiteDetail?

    private let api: any WebsitesProviding
    private let offlineStore: OfflineStore?
    private let networkStatus: (any NetworkStatusProviding)?
    weak var writeQueue: WriteQueue?
    private var isRefreshingList = false

    public init(
        api: any WebsitesProviding,
        cache: CacheClient,
        offlineStore: OfflineStore? = nil,
        networkStatus: (any NetworkStatusProviding)? = nil
    ) {
        self.api = api
        self.offlineStore = offlineStore
        self.networkStatus = networkStatus
        super.init(cache: cache)
    }

    // MARK: - CachedStoreBase Overrides

    public override var cacheKey: String { CacheKeys.websitesList }
    public override var cacheTTL: TimeInterval { CachePolicy.websitesList }

    public override func fetchFromAPI() async throws -> WebsitesResponse {
        try await api.list()
    }

    public override func applyData(_ data: WebsitesResponse, persist: Bool) {
        applyListUpdate(data.items, persist: persist)
    }

    public override func backgroundRefresh() async {
        await refreshList()
    }

    // MARK: - Public API

    public func loadList(force: Bool = false) async throws {
        if !force {
            let cached: WebsitesResponse? = cache.get(key: cacheKey)
            if let cached {
                applyListUpdate(cached.items, persist: false)
                Task { [weak self] in
                    await self?.refreshList()
                }
                return
            }
            if let offline = offlineStore?.get(key: cacheKey, as: WebsitesResponse.self) {
                applyListUpdate(offline.items, persist: false)
                if !(networkStatus?.isOffline ?? false) {
                    Task { [weak self] in
                        await self?.refreshList()
                    }
                }
                return
            }
        }
        let remote = try await fetchFromAPI()
        applyListUpdate(remote.items, persist: true)
        cache.set(key: cacheKey, value: remote, ttlSeconds: cacheTTL)
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
                cache.set(key: CacheKeys.websiteDetail(id: updated.id), value: updated, ttlSeconds: CachePolicy.websiteDetail)
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
                cache.set(key: CacheKeys.websiteDetail(id: updated.id), value: updated, ttlSeconds: CachePolicy.websiteDetail)
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
        offlineStore?.remove(key: CacheKeys.websiteDetail(id: id))
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

    public func attachWriteQueue(_ writeQueue: WriteQueue) {
        self.writeQueue = writeQueue
    }

    public func loadFromOffline() async {
        guard let offline = offlineStore?.get(key: cacheKey, as: WebsitesResponse.self) else { return }
        applyListUpdate(offline.items, persist: false)
    }

    public func saveOfflineSnapshot() async {
        persistListCache()
        if let active {
            let key = CacheKeys.websiteDetail(id: active.id)
            let lastSyncAt = offlineStore?.lastSyncAt(for: key)
            offlineStore?.set(key: key, entityType: "website", value: active, lastSyncAt: lastSyncAt)
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

    // MARK: - Private

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

    private func refreshDetail(id: String) async {
        do {
            let response = try await api.get(id: id)
            applyDetailUpdate(response, persist: true)
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
        updateWidgetData(from: incoming)
    }

    // MARK: - Widget Data

    func updateWidgetData(from items: [WebsiteItem]) {
        let pinnedSites = items
            .filter { $0.pinned && !$0.archived }
            .sorted { ($0.pinnedOrder ?? Int.max) < ($1.pinnedOrder ?? Int.max) }
            .map { WidgetWebsite(from: $0) }
        let displaySites = Array(pinnedSites.prefix(10))
        let data = WidgetWebsiteData(websites: displaySites, totalCount: pinnedSites.count)
        WidgetDataManager.shared.store(data, for: .websites)
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
            cache.set(key: CacheKeys.websiteDetail(id: incoming.id), value: incoming, ttlSeconds: CachePolicy.websiteDetail)
            let lastSyncAt = Date()
            offlineStore?.set(
                key: CacheKeys.websiteDetail(id: incoming.id),
                entityType: "website",
                value: incoming,
                lastSyncAt: lastSyncAt
            )
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
        cache.set(key: CacheKeys.websitesList, value: response, ttlSeconds: CachePolicy.websitesList)
        let lastSyncAt = Date()
        offlineStore?.set(
            key: CacheKeys.websitesList,
            entityType: "websitesList",
            value: response,
            lastSyncAt: lastSyncAt
        )
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

extension WebsitesStore {
    func currentUpdatedAt(id: String) -> String? {
        websiteItem(for: id)?.updatedAt
    }

    func enqueueRename(id: String, title: String) async throws {
        guard let writeQueue else { throw WriteQueueError.missingQueue }
        let operationId = UUID().uuidString
        let payload = WebsiteOperationPayload(
            operationId: operationId,
            op: "rename",
            id: id,
            title: title,
            clientUpdatedAt: websiteItem(for: id)?.updatedAt
        )
        let snapshot = makeServerSnapshot(websiteId: id)
        try await writeQueue.enqueue(
            operation: .rename,
            entityType: .website,
            entityId: id,
            payload: payload,
            serverSnapshot: snapshot
        )
        applyLocalUpdate(id: id) { item in
            WebsiteItem(
                id: item.id,
                title: title,
                url: item.url,
                domain: item.domain,
                savedAt: item.savedAt,
                publishedAt: item.publishedAt,
                pinned: item.pinned,
                pinnedOrder: item.pinnedOrder,
                archived: item.archived,
                youtubeTranscripts: item.youtubeTranscripts,
                updatedAt: item.updatedAt,
                lastOpenedAt: item.lastOpenedAt,
                deletedAt: item.deletedAt
            )
        }
    }

    func enqueuePin(id: String, pinned: Bool) async throws {
        guard let writeQueue else { throw WriteQueueError.missingQueue }
        let operationId = UUID().uuidString
        let payload = WebsiteOperationPayload(
            operationId: operationId,
            op: "pin",
            id: id,
            pinned: pinned,
            clientUpdatedAt: websiteItem(for: id)?.updatedAt
        )
        let snapshot = makeServerSnapshot(websiteId: id)
        try await writeQueue.enqueue(
            operation: .pin,
            entityType: .website,
            entityId: id,
            payload: payload,
            serverSnapshot: snapshot
        )
        applyLocalUpdate(id: id) { item in
            WebsiteItem(
                id: item.id,
                title: item.title,
                url: item.url,
                domain: item.domain,
                savedAt: item.savedAt,
                publishedAt: item.publishedAt,
                pinned: pinned,
                pinnedOrder: item.pinnedOrder,
                archived: item.archived,
                youtubeTranscripts: item.youtubeTranscripts,
                updatedAt: item.updatedAt,
                lastOpenedAt: item.lastOpenedAt,
                deletedAt: item.deletedAt
            )
        }
    }

    func enqueueArchive(id: String, archived: Bool) async throws {
        guard let writeQueue else { throw WriteQueueError.missingQueue }
        let operationId = UUID().uuidString
        let payload = WebsiteOperationPayload(
            operationId: operationId,
            op: "archive",
            id: id,
            archived: archived,
            clientUpdatedAt: websiteItem(for: id)?.updatedAt
        )
        let snapshot = makeServerSnapshot(websiteId: id)
        try await writeQueue.enqueue(
            operation: .archive,
            entityType: .website,
            entityId: id,
            payload: payload,
            serverSnapshot: snapshot
        )
        applyLocalUpdate(id: id) { item in
            WebsiteItem(
                id: item.id,
                title: item.title,
                url: item.url,
                domain: item.domain,
                savedAt: item.savedAt,
                publishedAt: item.publishedAt,
                pinned: item.pinned,
                pinnedOrder: item.pinnedOrder,
                archived: archived,
                youtubeTranscripts: item.youtubeTranscripts,
                updatedAt: item.updatedAt,
                lastOpenedAt: item.lastOpenedAt,
                deletedAt: item.deletedAt
            )
        }
        if archived, active?.id == id {
            active = nil
        }
    }

    func enqueueDelete(id: String) async throws {
        guard let writeQueue else { throw WriteQueueError.missingQueue }
        let operationId = UUID().uuidString
        let payload = WebsiteOperationPayload(
            operationId: operationId,
            op: "delete",
            id: id,
            clientUpdatedAt: websiteItem(for: id)?.updatedAt
        )
        let snapshot = makeServerSnapshot(websiteId: id)
        try await writeQueue.enqueue(
            operation: .delete,
            entityType: .website,
            entityId: id,
            payload: payload,
            serverSnapshot: snapshot
        )
        removeItem(id: id, persist: true)
    }

    func applySyncItem(_ item: WebsiteItem) {
        if item.deletedAt != nil {
            removeItem(id: item.id, persist: true)
            return
        }
        updateListItem(item, persist: true)
    }

    private func applyLocalUpdate(id: String, update: (WebsiteItem) -> WebsiteItem) {
        guard let current = websiteItem(for: id) else { return }
        let updated = update(current)
        updateListItem(updated, persist: true)
    }

    private func websiteItem(for id: String) -> WebsiteItem? {
        if let item = items.first(where: { $0.id == id }) {
            return item
        }
        if let active, active.id == id {
            return WebsiteItem(
                id: active.id,
                title: active.title,
                url: active.url,
                domain: active.domain,
                savedAt: active.savedAt,
                publishedAt: active.publishedAt,
                pinned: active.pinned,
                pinnedOrder: active.pinnedOrder,
                archived: active.archived,
                youtubeTranscripts: active.youtubeTranscripts,
                updatedAt: active.updatedAt,
                lastOpenedAt: active.lastOpenedAt,
                deletedAt: nil
            )
        }
        return nil
    }

    private func makeServerSnapshot(websiteId: String) -> ServerSnapshot? {
        guard let item = websiteItem(for: websiteId) else { return nil }
        let snapshot = WebsiteSnapshot(
            updatedAt: item.updatedAt,
            title: item.title,
            pinned: item.pinned,
            pinnedOrder: item.pinnedOrder,
            archived: item.archived
        )
        return ServerSnapshot(
            entityType: .website,
            entityId: websiteId,
            capturedAt: Date(),
            payload: .website(snapshot)
        )
    }
}
