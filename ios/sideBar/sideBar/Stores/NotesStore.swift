import Foundation
import Combine

@MainActor
public final class NotesStore: ObservableObject {
    @Published public private(set) var tree: FileTree? = nil
    @Published public private(set) var activeNote: NotePayload? = nil

    private let api: any NotesProviding
    private let cache: CacheClient

    public init(api: any NotesProviding, cache: CacheClient) {
        self.api = api
        self.cache = cache
    }

    public func loadTree(force: Bool = false) async throws {
        if !force, let cached: FileTree = cache.get(key: CacheKeys.notesTree) {
            tree = cached
            return
        }
        let response = try await api.listTree()
        tree = response
        cache.set(key: CacheKeys.notesTree, value: response, ttlSeconds: CachePolicy.notesTree)
    }

    public func loadNote(id: String, force: Bool = false) async throws {
        let cacheKey = CacheKeys.note(id: id)
        if !force, let cached: NotePayload = cache.get(key: cacheKey) {
            activeNote = cached
            return
        }
        let response = try await api.getNote(id: id)
        activeNote = response
        cache.set(key: cacheKey, value: response, ttlSeconds: CachePolicy.noteContent)
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

    public func reset() {
        tree = nil
        activeNote = nil
    }
}
