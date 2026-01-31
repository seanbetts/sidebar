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

    private let api: any NotesProviding
    let offlineStore: OfflineStore?
    let networkStatus: (any NetworkStatusProviding)?
    weak var writeQueue: WriteQueue?
    weak var spotlightIndexer: (any SpotlightIndexing)?
    private var isRefreshingTree = false
    private var isRefreshingArchivedTree = false
    private var refreshingNotes = Set<String>()
    private let archivedNoteRetentionDays = 7
    private let archivedNotePrefetchLimit = 50
    private let archivedTreeLimit = 500
    private var archivedSummary: ArchivedSummary?
    private var archivedTreeSyncedAt: String?
    private var archivedSyncLoaded = false
    private var isPrefetchingArchivedNotes = false

    public init(
        api: any NotesProviding,
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
        if !force {
            let cached: FileTree? = cache.get(key: cacheKey)
            if let cached {
                applyTreeUpdate(cached, persist: false)
                Task { [weak self] in
                    await self?.refreshTree()
                }
                return
            }
            if let offline = offlineStore?.get(key: cacheKey, as: FileTree.self) {
                applyTreeUpdate(offline, persist: false)
                if networkStatus?.isNetworkAvailable ?? true {
                    Task { [weak self] in
                        await self?.refreshTree()
                    }
                }
                return
            }
        }
        let remote = try await fetchFromAPI()
        applyTreeUpdate(remote, persist: true)
        cache.set(key: cacheKey, value: remote, ttlSeconds: cacheTTL)
    }

    public func loadArchivedTree(force: Bool = false) async throws {
        if !force {
            let cached: FileTree? = cache.get(key: CacheKeys.notesArchivedTree)
            if let cached {
                applyArchivedTreeUpdate(cached, persist: false)
                if networkStatus?.isNetworkAvailable ?? true {
                    Task { [weak self] in
                        await self?.refreshArchivedTree()
                    }
                }
                return
            }
            if let offline = offlineStore?.get(key: CacheKeys.notesArchivedTree, as: FileTree.self) {
                applyArchivedTreeUpdate(offline, persist: false)
                if networkStatus?.isNetworkAvailable ?? true {
                    Task { [weak self] in
                        await self?.refreshArchivedTree()
                    }
                }
                return
            }
        }
        guard networkStatus?.isNetworkAvailable ?? true else {
            return
        }
        let remote = try await api.listArchivedTree(limit: archivedTreeLimit, offset: 0)
        applyArchivedTreeUpdate(remote, persist: true)
        archivedTreeSyncedAt = archivedSummary?.lastUpdated
        persistArchivedSyncToken()
    }

    public func loadNote(id: String, force: Bool = false) async throws {
        let cacheKey = CacheKeys.note(id: id)
        if !force, let cached: NotePayload = cache.get(key: cacheKey) {
            applyNoteUpdate(cached, persist: false)
            Task { [weak self] in
                await self?.refreshNote(id: id)
            }
            return
        }
        if !force, let offline = offlineStore?.get(key: cacheKey, as: NotePayload.self) {
            applyNoteUpdate(offline, persist: false)
            if networkStatus?.isNetworkAvailable ?? true {
                Task { [weak self] in
                    await self?.refreshNote(id: id)
                }
            }
            return
        }
        let response = try await api.getNote(id: id)
        applyNoteUpdate(response, persist: true)
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
    }

    public func applyEditorUpdate(_ note: NotePayload) {
        applyNoteUpdate(note, persist: true)
    }

    public func applyRealtimeEvent(_ payload: RealtimePayload<NoteRealtimeRecord>) async {
        let noteId = payload.record?.id ?? payload.oldRecord?.id
        if payload.eventType == .delete {
            if let noteId, activeNote?.id == noteId {
                activeNote = nil
            }
            if let noteId {
                // Get the path before invalidating so we can remove from Spotlight
                if let note = notePayload(forId: noteId) {
                    removeNoteFromSpotlight(path: note.path)
                }
                invalidateNote(id: noteId)
            }
        } else if let record = payload.record, let mapped = RealtimeMappers.mapNote(record) {
            applyNoteUpdate(mapped, persist: true)
        }
        await refreshTree()
    }

    public func reset() {
        tree = nil
        archivedTree = nil
        activeNote = nil
    }

    // MARK: - Private

    private func refreshTree() async {
        guard !isRefreshingTree else {
            return
        }
        isRefreshingTree = true
        defer { isRefreshingTree = false }
        do {
            let response = try await api.listTree()
            applyTreeUpdate(response, persist: true)
        } catch {
            // Ignore background refresh failures; cache remains source of truth.
        }
    }

    private func refreshArchivedTree(force: Bool = false) async {
        guard !isRefreshingArchivedTree else {
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
            Task { [weak self] in
                await self?.prefetchArchivedNotes(from: response)
            }
        } catch {
            // Ignore background refresh failures; cache remains source of truth.
        }
    }

    private func refreshNote(id: String) async {
        guard !refreshingNotes.contains(id) else {
            return
        }
        refreshingNotes.insert(id)
        defer { refreshingNotes.remove(id) }
        do {
            let response = try await api.getNote(id: id)
            applyNoteUpdate(response, persist: true)
        } catch {
            // Ignore background refresh failures; cache remains source of truth.
        }
    }

    func applyTreeUpdate(_ incoming: FileTree, persist: Bool) {
        guard shouldUpdateTree(incoming) else {
            return
        }
        updateArchivedSummary(from: incoming, persist: persist)
        let merged = mergeArchivedSummary(into: incoming)
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
        }
        updateWidgetData(from: merged)
    }

    func applyArchivedTreeUpdate(_ incoming: FileTree, persist: Bool) {
        let merged = mergeArchivedSummary(into: incoming)
        updateArchivedSummary(from: merged, persist: false)
        archivedTree = merged
        if persist {
            cache.set(key: CacheKeys.notesArchivedTree, value: merged, ttlSeconds: cacheTTL)
            let lastSyncAt = Date()
            offlineStore?.set(
                key: CacheKeys.notesArchivedTree,
                entityType: "notesArchivedTree",
                value: merged,
                lastSyncAt: lastSyncAt
            )
        }
    }

    func makeTree(children: [FileNode]) -> FileTree {
        FileTree(
            children: children,
            archivedCount: archivedSummary?.count,
            archivedLastUpdated: archivedSummary?.lastUpdated
        )
    }

    private func updateArchivedSummary(from tree: FileTree, persist: Bool) {
        let summary = ArchivedSummary(
            count: tree.archivedCount,
            lastUpdated: tree.archivedLastUpdated
        )
        guard !summary.isEmpty else {
            return
        }
        archivedSummary = summary
        if persist, summary.count == 0 {
            let empty = FileTree(
                children: [],
                archivedCount: summary.count,
                archivedLastUpdated: summary.lastUpdated
            )
            applyArchivedTreeUpdate(empty, persist: true)
            archivedTreeSyncedAt = summary.lastUpdated
            persistArchivedSyncToken()
        }
    }

    private func mergeArchivedSummary(into tree: FileTree) -> FileTree {
        FileTree(
            children: tree.children,
            archivedCount: tree.archivedCount ?? archivedSummary?.count,
            archivedLastUpdated: tree.archivedLastUpdated ?? archivedSummary?.lastUpdated
        )
    }

    private func shouldRefreshArchivedTree(force: Bool) -> Bool {
        if force {
            return true
        }
        loadArchivedSyncTokenIfNeeded()
        if let summary = archivedSummary {
            if summary.count == 0 {
                return false
            }
            if archivedTree == nil {
                return true
            }
            guard let serverUpdated = summary.lastUpdated else {
                return archivedTree == nil
            }
            let syncedAt = archivedTreeSyncedAt ?? archivedTree?.archivedLastUpdated
            if let syncedAt {
                return syncedAt != serverUpdated
            }
            return true
        }
        return true
    }

    private func loadArchivedSyncTokenIfNeeded() {
        guard !archivedSyncLoaded else {
            return
        }
        archivedSyncLoaded = true
        archivedTreeSyncedAt = offlineStore?.get(
            key: CacheKeys.notesArchivedSync,
            as: String.self
        )
    }

    private func persistArchivedSyncToken() {
        guard let archivedTreeSyncedAt else {
            return
        }
        let lastSyncAt = Date()
        offlineStore?.set(
            key: CacheKeys.notesArchivedSync,
            entityType: "notesArchivedSync",
            value: archivedTreeSyncedAt,
            lastSyncAt: lastSyncAt
        )
    }

    private func shouldUpdateTree(_ incoming: FileTree) -> Bool {
        guard let current = tree else {
            return true
        }
        if current.archivedCount != incoming.archivedCount ||
            current.archivedLastUpdated != incoming.archivedLastUpdated {
            return true
        }
        return FileTreeSignature.make(current) != FileTreeSignature.make(incoming)
    }

    func applyNoteUpdate(_ incoming: NotePayload, persist: Bool) {
        guard shouldUpdateActiveNote(incoming) else {
            return
        }
        activeNote = incoming
        if persist {
            if shouldPersistNote(incoming) {
                persistNote(incoming)
                indexNoteInSpotlight(incoming)
            } else {
                clearCachedNote(incoming)
            }
        }
    }

    private func indexNoteInSpotlight(_ note: NotePayload) {
        guard let indexer = spotlightIndexer else { return }
        let spotlightNote = SpotlightNote(
            path: note.path,
            name: note.name,
            content: note.content,
            modified: note.modified.map { Date(timeIntervalSince1970: $0) }
        )
        Task {
            await indexer.indexNote(spotlightNote)
        }
    }

    private func removeNoteFromSpotlight(path: String) {
        guard let indexer = spotlightIndexer else { return }
        Task {
            await indexer.removeNote(path: path)
        }
    }

    private func shouldUpdateActiveNote(_ incoming: NotePayload) -> Bool {
        guard let current = activeNote else {
            return true
        }
        return current.modified != incoming.modified ||
            current.content != incoming.content ||
            current.name != incoming.name ||
            current.path != incoming.path
    }

    func shouldPersistNote(_ note: NotePayload) -> Bool {
        guard isArchived(note) else {
            return true
        }
        guard let modified = note.modified else {
            return false
        }
        guard let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -archivedNoteRetentionDays,
            to: Date()
        ) else {
            return false
        }
        return Date(timeIntervalSince1970: modified) >= cutoff
    }

    private func persistNote(_ note: NotePayload) {
        let idKey = CacheKeys.note(id: note.id)
        let pathKey = CacheKeys.note(id: note.path)
        cache.set(key: idKey, value: note, ttlSeconds: CachePolicy.noteContent)
        cache.set(key: pathKey, value: note, ttlSeconds: CachePolicy.noteContent)
        let lastSyncAt = Date()
        offlineStore?.set(key: idKey, entityType: "note", value: note, lastSyncAt: lastSyncAt)
        offlineStore?.set(key: pathKey, entityType: "note", value: note, lastSyncAt: lastSyncAt)
    }

    private func clearCachedNote(_ note: NotePayload) {
        let idKey = CacheKeys.note(id: note.id)
        let pathKey = CacheKeys.note(id: note.path)
        cache.remove(key: idKey)
        cache.remove(key: pathKey)
        offlineStore?.remove(key: idKey)
        offlineStore?.remove(key: pathKey)
    }

    private func isArchived(_ note: NotePayload) -> Bool {
        if let tree, findNode(path: note.path, in: tree.children)?.archived == true {
            return true
        }
        if let archivedTree, findNode(path: note.path, in: archivedTree.children)?.archived == true {
            return true
        }
        return false
    }

    private func prefetchArchivedNotes(from tree: FileTree) async {
        guard archivedNotePrefetchLimit > 0 else { return }
        guard !(networkStatus?.isOffline ?? false) else { return }
        guard !isPrefetchingArchivedNotes else { return }
        isPrefetchingArchivedNotes = true
        defer { isPrefetchingArchivedNotes = false }

        let nodes = archivedNoteNodes(from: tree.children)
        let candidates = nodes.filter { isWithinArchivedRetention(modified: $0.modified) }
        let uncached = candidates.filter { !hasCachedNote(id: $0.path) }
        guard !uncached.isEmpty else { return }
        let sorted = uncached.sorted { ($0.modified ?? 0) > ($1.modified ?? 0) }
        for node in sorted.prefix(archivedNotePrefetchLimit) {
            do {
                let note = try await api.getNote(id: node.path)
                if shouldPersistNote(note) {
                    persistNote(note)
                } else {
                    clearCachedNote(note)
                }
            } catch {
                continue
            }
        }
    }

    private func archivedNoteNodes(from nodes: [FileNode]) -> [FileNode] {
        var collected: [FileNode] = []
        for node in nodes {
            if node.type == .file {
                collected.append(node)
            }
            if let children = node.children {
                collected.append(contentsOf: archivedNoteNodes(from: children))
            }
        }
        return collected
    }

    private func isWithinArchivedRetention(modified: Double?) -> Bool {
        guard let modified else { return false }
        guard let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -archivedNoteRetentionDays,
            to: Date()
        ) else {
            return false
        }
        return Date(timeIntervalSince1970: modified) >= cutoff
    }

    private func findNode(path: String, in nodes: [FileNode]) -> FileNode? {
        for node in nodes {
            if node.path == path {
                return node
            }
            if let children = node.children, let found = findNode(path: path, in: children) {
                return found
            }
        }
        return nil
    }

    // MARK: - Widget Data

    func updateWidgetData(from tree: FileTree) {
        let pinnedNotes = flattenNotes(from: tree.children)
            .filter { $0.pinned }
            .sorted { ($0.pinnedOrder ?? Int.max) < ($1.pinnedOrder ?? Int.max) }
        let displayNotes = Array(pinnedNotes.prefix(10))
        let data = WidgetNoteData(notes: displayNotes, totalCount: pinnedNotes.count)
        WidgetDataManager.shared.store(data, for: .notes)
    }

    private func flattenNotes(from nodes: [FileNode]) -> [WidgetNote] {
        var notes: [WidgetNote] = []
        for node in nodes {
            if node.type == .file, node.archived != true {
                notes.append(WidgetNote(from: node))
            }
            if let children = node.children {
                notes.append(contentsOf: flattenNotes(from: children))
            }
        }
        return notes
    }
}
