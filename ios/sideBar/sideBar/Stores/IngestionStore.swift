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
    @Published public private(set) var items: [IngestionListItem] = []
    @Published public private(set) var activeMeta: IngestionMetaResponse?
    @Published public private(set) var isOffline: Bool = false

    private let api: any IngestionProviding
    private let offlineStore: OfflineStore?
    private let networkStatus: (any NetworkStatusProviding)?
    weak var writeQueue: WriteQueue?
    private var remoteItems: [IngestionListItem] = []
    private var localItems: [String: IngestionListItem] = [:]
    private var localUploadRecords: [String: LocalUploadRecord] = [:]
    private let userDefaults: UserDefaults
    private var isRefreshingList = false
    private var refreshingMetaIds = Set<String>()
    private let localUploadsKey = "ingestion.localUploads"

    public init(
        api: any IngestionProviding,
        cache: CacheClient,
        offlineStore: OfflineStore? = nil,
        networkStatus: (any NetworkStatusProviding)? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.api = api
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
        if !force {
            let cached: IngestionListResponse? = cache.get(key: cacheKey)
            if let cached {
                applyListUpdate(cached.items, persist: false)
                Task { [weak self] in
                    await self?.refreshList()
                }
                return
            }
            if let offline = offlineStore?.get(key: cacheKey, as: IngestionListResponse.self) {
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

    public func loadMeta(fileId: String, force: Bool = false) async throws {
        let cacheKey = CacheKeys.ingestionMeta(fileId: fileId)
        if !force, let cached: IngestionMetaResponse = cache.get(key: cacheKey) {
            applyMetaUpdate(cached, persist: false)
            Task { [weak self] in
                await self?.refreshMeta(fileId: fileId)
            }
            return
        }
        if !force, let offline = offlineStore?.get(key: cacheKey, as: IngestionMetaResponse.self) {
            applyMetaUpdate(offline, persist: false)
            if !(networkStatus?.isOffline ?? false) {
                Task { [weak self] in
                    await self?.refreshMeta(fileId: fileId)
                }
            }
            return
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
}
