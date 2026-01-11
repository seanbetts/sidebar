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
    private let store: NotesStore
    private var searchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    public init(
        api: any NotesProviding,
        store: NotesStore
    ) {
        self.api = api
        self.store = store

        store.$tree
            .sink { [weak self] tree in
                self?.tree = tree
            }
            .store(in: &cancellables)

        store.$activeNote
            .sink { [weak self] note in
                self?.activeNote = note
            }
            .store(in: &cancellables)
    }

    public func loadTree() async {
        errorMessage = nil
        do {
            try await store.loadTree()
        } catch {
            if tree == nil {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func loadNote(id: String) async {
        errorMessage = nil
        selectedNoteId = id
        do {
            try await store.loadNote(id: id)
        } catch {
            if activeNote == nil {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func selectNote(id: String) async {
        await loadNote(id: id)
    }

    public func clearSelection() {
        selectedNoteId = nil
        store.clearActiveNote()
    }

    public func applyRealtimeEvent(_ payload: RealtimePayload<NoteRealtimeRecord>) async {
        let noteId = payload.record?.id ?? payload.oldRecord?.id
        store.invalidateTree()
        if let noteId {
            store.invalidateNote(id: noteId)
        }
        if payload.eventType == .delete, selectedNoteId == noteId {
            selectedNoteId = nil
            store.clearActiveNote()
        }
        await loadTree()
        if let noteId, payload.eventType != .delete, selectedNoteId == noteId {
            await loadNote(id: noteId)
        }
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
