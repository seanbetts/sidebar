import Foundation
import Combine

// TODO: Revisit to prefer native-first data sources where applicable.

@MainActor
public final class NotesViewModel: ObservableObject {
    @Published public private(set) var tree: FileTree? = nil
    @Published public private(set) var activeNote: NotePayload? = nil
    @Published public private(set) var errorMessage: String? = nil

    private let api: any NotesProviding
    private let cache: CacheClient

    public init(api: any NotesProviding, cache: CacheClient) {
        self.api = api
        self.cache = cache
    }

    public func loadTree() async {
        errorMessage = nil
        let cached: FileTree? = cache.get(key: CacheKeys.notesTree)
        if let cached {
            tree = cached
        }
        do {
            let response = try await api.listTree()
            tree = response
            cache.set(key: CacheKeys.notesTree, value: response, ttlSeconds: CachePolicy.notesTree)
        } catch {
            if cached == nil {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func loadNote(id: String) async {
        errorMessage = nil
        let cacheKey = CacheKeys.note(id: id)
        let cached: NotePayload? = cache.get(key: cacheKey)
        if let cached {
            activeNote = cached
        }
        do {
            let response = try await api.getNote(id: id)
            activeNote = response
            cache.set(key: cacheKey, value: response, ttlSeconds: CachePolicy.noteContent)
        } catch {
            if cached == nil {
                errorMessage = error.localizedDescription
            }
        }
    }
}
