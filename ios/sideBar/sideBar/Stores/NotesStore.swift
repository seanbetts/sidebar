import Foundation
import Combine

@MainActor
public final class NotesStore: ObservableObject {
    @Published public private(set) var tree: FileTree? = nil
    @Published public private(set) var activeNote: NotePayload? = nil

    private let api: any NotesProviding
    private let cache: CacheClient
    private var isRefreshingTree = false

    public init(api: any NotesProviding, cache: CacheClient) {
        self.api = api
        self.cache = cache
    }

    public func loadTree(force: Bool = false) async throws {
        let cached: FileTree? = force ? nil : cache.get(key: CacheKeys.notesTree)
        if let cached {
            applyTreeUpdate(cached, persist: false)
            Task { [weak self] in
                await self?.refreshTree()
            }
            return
        }
        let response = try await api.listTree()
        applyTreeUpdate(response, persist: true)
    }

    public func loadNote(id: String, force: Bool = false) async throws {
        let cacheKey = CacheKeys.note(id: id)
        if !force, let cached: NotePayload = cache.get(key: cacheKey) {
            applyNoteUpdate(cached, persist: false)
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
                cache.remove(key: CacheKeys.note(id: noteId))
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

    private func applyTreeUpdate(_ incoming: FileTree, persist: Bool) {
        guard shouldUpdateTree(incoming) else {
            return
        }
        tree = incoming
        if persist {
            cache.set(key: CacheKeys.notesTree, value: incoming, ttlSeconds: CachePolicy.notesTree)
        }
    }

    private func shouldUpdateTree(_ incoming: FileTree) -> Bool {
        guard let current = tree else {
            return true
        }
        return FileTreeSignature.make(current) != FileTreeSignature.make(incoming)
    }

    private func applyNoteUpdate(_ incoming: NotePayload, persist: Bool) {
        guard shouldUpdateActiveNote(incoming) else {
            return
        }
        activeNote = incoming
        if persist {
            cache.set(key: CacheKeys.note(id: incoming.id), value: incoming, ttlSeconds: CachePolicy.noteContent)
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
}
