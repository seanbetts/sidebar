import Foundation
import Combine
#if canImport(WidgetKit)
import WidgetKit
#endif

// MARK: - NotesStore

/// Persistent store for notes file tree and active note content.
///
/// Manages the hierarchical file tree of notes and the currently selected note.
/// Uses `CachedStoreBase` for cache-first loading with background refresh.
///
/// ## Responsibilities
/// - Load and cache the notes file tree structure
/// - Load and cache individual note content
/// - Apply editor updates from `NotesEditorViewModel`
/// - Handle real-time note events (insert, update, delete)
public final class NotesStore: CachedStoreBase<FileTree> {
    @Published public internal(set) var tree: FileTree?
    @Published public internal(set) var archivedTree: FileTree?
    @Published public internal(set) var activeNote: NotePayload?

    let api: any NotesProviding
    let widgetDataManager: WidgetDataManager
    let offlineStore: OfflineStore?
    let networkStatus: (any NetworkStatusProviding)?
    weak var writeQueue: WriteQueue?
    weak var spotlightIndexer: (any SpotlightIndexing)?
    var isRefreshingTree = false
    var isRefreshingArchivedTree = false
    var refreshingNotes = Set<String>()
    var activeNoteRequestID: String?
    let archivedNoteRetentionDays = 7
    let archivedNotePrefetchLimit = 50
    let archivedTreeLimit = 500
    let archivedRefreshWaitTimeoutNanoseconds: UInt64
    let archivedRefreshPollIntervalNanoseconds: UInt64
    var archivedSummary: ArchivedSummary?
    var archivedTreeSyncedAt: String?
    var archivedSyncLoaded = false
    var isPrefetchingArchivedNotes = false

    public init(
        api: any NotesProviding,
        cache: CacheClient,
        widgetDataManager: WidgetDataManager = .shared,
        offlineStore: OfflineStore? = nil,
        networkStatus: (any NetworkStatusProviding)? = nil,
        archivedRefreshWaitTimeoutNanoseconds: UInt64 = 10_000_000_000,
        archivedRefreshPollIntervalNanoseconds: UInt64 = 50_000_000
    ) {
        self.api = api
        self.widgetDataManager = widgetDataManager
        self.offlineStore = offlineStore
        self.networkStatus = networkStatus
        let pollInterval = max(1, archivedRefreshPollIntervalNanoseconds)
        self.archivedRefreshPollIntervalNanoseconds = pollInterval
        self.archivedRefreshWaitTimeoutNanoseconds = max(pollInterval, archivedRefreshWaitTimeoutNanoseconds)
        super.init(cache: cache)
    }

    // MARK: - CachedStoreBase Overrides

    public override var cacheKey: String { CacheKeys.notesTree }
    public override var cacheTTL: TimeInterval { CachePolicy.notesTree }

    public override func fetchFromAPI() async throws -> FileTree {
        try await api.listTree()
    }

    public override func applyData(_ data: FileTree, persist: Bool) {
        applyTreeUpdate(data, persist: persist)
    }

    public override func backgroundRefresh() async {
        await refreshTree()
    }

    // MARK: - Public API

    public func loadTree(force: Bool = false) async throws {
        let treeCacheKey = self.cacheKey
        let offlineStore = offlineStore
        _ = try await loadWithCacheAndOffline(
            force: force,
            offline: { offlineStore?.get(key: treeCacheKey, as: FileTree.self) },
            isNetworkAvailable: networkStatus?.offlineCapabilityPolicy.canAttemptServerRead ?? true
        )
    }

    public func loadArchivedTree(force: Bool = false) async throws {
        let canAttemptServerRead = networkStatus?.offlineCapabilityPolicy.canAttemptServerRead ?? true
        if !force {
            let cached: FileTree? = cache.get(key: CacheKeys.notesArchivedTree)
            if let cached {
                applyArchivedTreeUpdate(cached, persist: false)
                if canAttemptServerRead {
                    await refreshArchivedTree()
                }
                return
            }
            if let offline = offlineStore?.get(key: CacheKeys.notesArchivedTree, as: FileTree.self) {
                applyArchivedTreeUpdate(offline, persist: false)
                if canAttemptServerRead {
                    await refreshArchivedTree()
                }
                return
            }
        }
        guard canAttemptServerRead else {
            return
        }
        let remote = try await api.listArchivedTree(limit: archivedTreeLimit, offset: 0)
        applyArchivedTreeUpdate(remote, persist: true)
        archivedTreeSyncedAt = archivedSummary?.lastUpdated
        persistArchivedSyncToken()
    }

    public func loadNote(id: String, force: Bool = false) async throws {
        activeNoteRequestID = id
        let cacheKey = CacheKeys.note(id: id)
        if !force, let cached: NotePayload = cache.get(key: cacheKey) {
            applyNoteUpdate(cached, persist: false, activeNoteMode: .matchingSelection)
            Task { [weak self] in
                await self?.refreshNote(id: id)
            }
            return
        }
        if !force, let offline = offlineStore?.get(key: cacheKey, as: NotePayload.self) {
            applyNoteUpdate(offline, persist: false, activeNoteMode: .matchingSelection)
            if networkStatus?.offlineCapabilityPolicy.canAttemptServerRead ?? true {
                Task { [weak self] in
                    await self?.refreshNote(id: id)
                }
            }
            return
        }
        let response = try await api.getNote(id: id)
        applyNoteUpdate(response, persist: true, activeNoteMode: .matchingSelection)
    }

    public func invalidateTree() {
        cache.remove(key: CacheKeys.notesTree)
    }

    public func invalidateNote(id: String) {
        cache.remove(key: CacheKeys.note(id: id))
        offlineStore?.remove(key: CacheKeys.note(id: id))
        if let note = notePayload(forPath: id) ?? notePayload(forId: id) {
            cache.remove(key: CacheKeys.note(id: note.id))
            cache.remove(key: CacheKeys.note(id: note.path))
            offlineStore?.remove(key: CacheKeys.note(id: note.id))
            offlineStore?.remove(key: CacheKeys.note(id: note.path))
        }
    }

    public func hasCachedNote(id: String) -> Bool {
        let cacheKey = CacheKeys.note(id: id)
        let cached: NotePayload? = cache.get(key: cacheKey)
        if cached != nil {
            return true
        }
        if let offlineStore, offlineStore.get(key: cacheKey, as: NotePayload.self) != nil {
            return true
        }
        return false
    }

    public func clearActiveNote() {
        activeNote = nil
        activeNoteRequestID = nil
    }

    public func applyEditorUpdate(_ note: NotePayload) {
        applyNoteUpdate(note, persist: true, activeNoteMode: .force)
    }

    public func applyRealtimeEvent(_ payload: RealtimePayload<NoteRealtimeRecord>) async {
        let noteId = payload.record?.id ?? payload.oldRecord?.id
        if payload.eventType == .delete {
            if let noteId, activeNote?.id == noteId {
                activeNote = nil
                activeNoteRequestID = nil
            }
            if let noteId {
                // Get the path before invalidating so we can remove from Spotlight
                if let note = notePayload(forId: noteId) {
                    removeNoteFromSpotlight(path: note.path)
                }
                invalidateNote(id: noteId)
            }
        } else if let record = payload.record, let mapped = RealtimeMappers.mapNote(record) {
            applyNoteUpdate(mapped, persist: true, activeNoteMode: .matchingSelection)
        }
        await refreshTree()
    }

    public func reset() {
        tree = nil
        archivedTree = nil
        activeNote = nil
        activeNoteRequestID = nil
    }

    // MARK: - Private

    func refreshTree() async {
        guard canAttemptBackgroundRefresh() else {
            return
        }
        guard !isRefreshingTree else {
            return
        }
        isRefreshingTree = true
        defer { isRefreshingTree = false }
        do {
            let response = try await api.listTree()
            applyTreeUpdate(response, persist: true)
            markBackgroundRefreshSuccess()
        } catch {
            markBackgroundRefreshFailure()
            // Ignore background refresh failures; cache remains source of truth.
        }
    }

    func refreshArchivedTree(force: Bool = false) async {
        if !force {
            guard canAttemptBackgroundRefresh() else {
                return
            }
        }
        if isRefreshingArchivedTree {
            await waitForArchivedTreeRefresh()
            return
        }
        guard shouldRefreshArchivedTree(force: force) else {
            return
        }
        isRefreshingArchivedTree = true
        defer { isRefreshingArchivedTree = false }
        do {
            let response = try await api.listArchivedTree(limit: archivedTreeLimit, offset: 0)
            applyArchivedTreeUpdate(response, persist: true)
            archivedTreeSyncedAt = archivedSummary?.lastUpdated
            persistArchivedSyncToken()
            markBackgroundRefreshSuccess()
            Task { [weak self] in
                await self?.prefetchArchivedNotes(from: response)
            }
        } catch {
            markBackgroundRefreshFailure()
            // Ignore background refresh failures; cache remains source of truth.
        }
    }

    func waitForArchivedTreeRefresh() async {
        var elapsed: UInt64 = 0
        while isRefreshingArchivedTree, elapsed < archivedRefreshWaitTimeoutNanoseconds {
            try? await Task.sleep(nanoseconds: archivedRefreshPollIntervalNanoseconds)
            elapsed += archivedRefreshPollIntervalNanoseconds
        }
    }

    func refreshNote(id: String) async {
        guard canAttemptBackgroundRefresh() else {
            return
        }
        guard !refreshingNotes.contains(id) else {
            return
        }
        refreshingNotes.insert(id)
        defer { refreshingNotes.remove(id) }
        do {
            let response = try await api.getNote(id: id)
            applyNoteUpdate(response, persist: true, activeNoteMode: .matchingSelection)
            markBackgroundRefreshSuccess()
        } catch {
            markBackgroundRefreshFailure()
            // Ignore background refresh failures; cache remains source of truth.
        }
    }

    func applyTreeUpdate(_ incoming: FileTree, persist: Bool) {
        let merged = mergeArchivedSummary(into: incoming)
        syncActiveNote(with: merged, persist: persist)
        guard shouldUpdateTree(incoming) else {
            updateWidgetData(from: merged)
            return
        }
        updateArchivedSummary(from: incoming, persist: persist)
        tree = merged
        if persist {
            cache.set(key: CacheKeys.notesTree, value: merged, ttlSeconds: CachePolicy.notesTree)
            let lastSyncAt = Date()
            offlineStore?.set(
                key: cacheKey,
                entityType: "notesTree",
                value: merged,
                lastSyncAt: lastSyncAt
            )
            indexNotesFromTree(merged)
        }
        updateWidgetData(from: merged)
    }
}
