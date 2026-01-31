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
    @Published public internal(set) var activeNote: NotePayload?

    private let api: any NotesProviding
    let offlineStore: OfflineStore?
    let networkStatus: (any NetworkStatusProviding)?
    weak var writeQueue: WriteQueue?
    private var isRefreshingTree = false
    private var refreshingNotes = Set<String>()
    private let archivedNoteRetentionDays = 7

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
                invalidateNote(id: noteId)
            }
        } else if let record = payload.record, let mapped = RealtimeMappers.mapNote(record) {
            applyNoteUpdate(mapped, persist: true)
        }
        await refreshTree()
    }

    public func reset() {
        tree = nil
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
        tree = incoming
        if persist {
            cache.set(key: CacheKeys.notesTree, value: incoming, ttlSeconds: CachePolicy.notesTree)
            let lastSyncAt = Date()
            offlineStore?.set(key: cacheKey, entityType: "notesTree", value: incoming, lastSyncAt: lastSyncAt)
        }
        updateWidgetData(from: incoming)
    }

    private func shouldUpdateTree(_ incoming: FileTree) -> Bool {
        guard let current = tree else {
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
            } else {
                clearCachedNote(incoming)
            }
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
        guard let tree else {
            return false
        }
        return findNode(path: note.path, in: tree.children)?.archived == true
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
