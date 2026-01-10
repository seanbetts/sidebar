import Foundation
import Combine

@MainActor
public final class NotesViewModel: ObservableObject {
    @Published public private(set) var tree: FileTree? = nil
    @Published public private(set) var activeNote: NotePayload? = nil
    @Published public private(set) var selectedNoteId: String? = nil
    @Published public var searchQuery: String = ""
    @Published public private(set) var searchResults: [FileNode] = []
    @Published public private(set) var isSearching: Bool = false
    @Published public private(set) var errorMessage: String? = nil

    private let api: any NotesProviding
    private let cache: CacheClient
    private var searchTask: Task<Void, Never>?

    public init(
        api: any NotesProviding,
        cache: CacheClient
    ) {
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
        selectedNoteId = id
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

    public func selectNote(id: String) async {
        await loadNote(id: id)
    }

    public func updateSearch(query: String) {
        searchQuery = query
        searchTask?.cancel()
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            await self?.performSearch(query: trimmed)
        }
    }

    private func performSearch(query: String) async {
        do {
            let results = try await api.search(query: query, limit: 50)
            searchResults = results
            isSearching = false
        } catch {
            errorMessage = error.localizedDescription
            searchResults = []
            isSearching = false
        }
    }
}
