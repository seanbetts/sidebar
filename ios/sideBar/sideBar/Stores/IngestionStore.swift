import Foundation
import Combine

// MARK: - IngestionStore

/// Persistent store for ingested files and their processing metadata.
///
/// Manages both remote file list and locally-initiated uploads. Merges local
/// upload state with server-side data for seamless optimistic UI updates.
///
/// ## Responsibilities
/// - Load and cache the ingested files list
/// - Track local upload items before server confirmation
/// - Load and cache file metadata (derivatives, content)
/// - Handle offline state detection
/// - Handle real-time file job events
public final class IngestionStore: CachedStoreBase<IngestionListResponse> {
    @Published public internal(set) var items: [IngestionListItem] = []
    @Published public internal(set) var activeMeta: IngestionMetaResponse?
    @Published public internal(set) var isOffline: Bool = false

    let api: any IngestionProviding
    let widgetDataManager: WidgetDataManager
    let offlineStore: OfflineStore?
    let networkStatus: (any NetworkStatusProviding)?
    weak var writeQueue: WriteQueue?
    weak var spotlightIndexer: (any SpotlightIndexing)?
    var remoteItems: [IngestionListItem] = []
    var localItems: [String: IngestionListItem] = [:]
    var localUploadRecords: [String: LocalUploadRecord] = [:]
    let userDefaults: UserDefaults
    var isRefreshingList = false
    var refreshingMetaIds = Set<String>()
    var inFlightListLoadTask: Task<Void, Error>?
    let localUploadsKey = "ingestion.localUploads"
    var canAttemptServerRead: Bool {
        networkStatus?.offlineCapabilityPolicy.canAttemptServerRead ?? true
    }

    public init(
        api: any IngestionProviding,
        cache: CacheClient,
        widgetDataManager: WidgetDataManager = .shared,
        offlineStore: OfflineStore? = nil,
        networkStatus: (any NetworkStatusProviding)? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.api = api
        self.widgetDataManager = widgetDataManager
        self.offlineStore = offlineStore
        self.networkStatus = networkStatus
        self.userDefaults = userDefaults
        super.init(cache: cache)
        loadLocalUploads()
    }

    // MARK: - CachedStoreBase Overrides

    public override var cacheKey: String { CacheKeys.ingestionList }
    public override var cacheTTL: TimeInterval { CachePolicy.ingestionList }

    public override func fetchFromAPI() async throws -> IngestionListResponse {
        let response = try await api.list()
        isOffline = false
        return response
    }

    public override func applyData(_ data: IngestionListResponse, persist: Bool) {
        applyListUpdate(data.items, persist: persist)
    }

    public override func backgroundRefresh() async {
        await refreshList()
    }

    // MARK: - Public API

    public func loadList(force: Bool = false) async throws {
        if let inFlight = inFlightListLoadTask {
            return try await inFlight.value
        }

        let task = Task<Void, Error> { @MainActor [weak self] in
            guard let self else { return }
            let listCacheKey = self.cacheKey
            let offlineStore = self.offlineStore
            _ = try await self.loadWithCacheAndOffline(
                force: force,
                offline: { offlineStore?.get(key: listCacheKey, as: IngestionListResponse.self) },
                isNetworkAvailable: self.canAttemptServerRead
            )
        }
        inFlightListLoadTask = task
        defer { inFlightListLoadTask = nil }
        try await task.value
    }

    public func loadMeta(fileId: String, force: Bool = false) async throws {
        let cacheKey = CacheKeys.ingestionMeta(fileId: fileId)
        if !force, let cached: IngestionMetaResponse = cache.get(key: cacheKey) {
            applyMetaUpdate(cached, persist: false)
            if canAttemptServerRead {
                Task { [weak self] in
                    await self?.refreshMeta(fileId: fileId)
                }
            }
            return
        }
        if !force, let offline = offlineStore?.get(key: cacheKey, as: IngestionMetaResponse.self) {
            applyMetaUpdate(offline, persist: false)
            if canAttemptServerRead {
                Task { [weak self] in
                    await self?.refreshMeta(fileId: fileId)
                }
            }
            return
        }
        guard canAttemptServerRead else {
            throw IngestionOfflineUnavailableError(message: "This file isn't available offline yet.")
        }
        let response = try await api.getMeta(fileId: fileId)
        isOffline = false
        applyMetaUpdate(response, persist: true)
    }

    public func invalidateList() {
        cache.remove(key: CacheKeys.ingestionList)
    }

    public func clearActiveMeta() {
        activeMeta = nil
    }

    public func reset() {
        inFlightListLoadTask?.cancel()
        inFlightListLoadTask = nil
        items = []
        remoteItems = []
        localItems = [:]
        localUploadRecords = [:]
        activeMeta = nil
        userDefaults.removeObject(forKey: localUploadsKey)
    }

    public func attachWriteQueue(_ writeQueue: WriteQueue) {
        self.writeQueue = writeQueue
    }

    public func loadFromOffline() async {
        guard let offline = offlineStore?.get(key: cacheKey, as: IngestionListResponse.self) else { return }
        applyListUpdate(offline.items, persist: false)
    }

    public func saveOfflineSnapshot() async {
        persistListCache()
        if let meta = activeMeta {
            let key = CacheKeys.ingestionMeta(fileId: meta.file.id)
            let lastSyncAt = offlineStore?.lastSyncAt(for: key)
            offlineStore?.set(key: key, entityType: "file", value: meta, lastSyncAt: lastSyncAt)
        }
    }

    func cachedDerivativeContent(fileId: String, kind: String) -> Data? {
        let key = CacheKeys.ingestionDerivativeContent(fileId: fileId, kind: kind)
        if let cached: Data = cache.get(key: key) {
            return cached
        }
        return offlineStore?.get(key: key, as: Data.self)
    }

    func persistDerivativeContent(_ data: Data, fileId: String, kind: String) {
        let key = CacheKeys.ingestionDerivativeContent(fileId: fileId, kind: kind)
        cache.set(key: key, value: data, ttlSeconds: CachePolicy.ingestionMeta)
        let lastSyncAt = offlineStore?.lastSyncAt(for: key)
        offlineStore?.set(
            key: key,
            entityType: "ingestionDerivativeContent",
            value: data,
            lastSyncAt: lastSyncAt
        )
    }
}

struct IngestionOfflineUnavailableError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}
