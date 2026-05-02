import Foundation
import sideBarShared
import Combine

// MARK: - NotesViewModel

@MainActor
/// Manages the notes file tree, note selection, and search functionality.
///
/// This ViewModel acts as a coordinator between the UI and the `NotesStore`, providing:
/// - File tree loading and navigation
/// - Note creation, move, archive, and delete operations
/// - Folder management (create, rename, delete)
/// - Debounced search with `ManagedTask`
/// - Real-time event handling for live updates
///
/// ## Data Flow
/// The ViewModel subscribes to `NotesStore` publishers and mirrors state for SwiftUI binding.
/// All mutations flow through the store, which handles caching and persistence.
///
/// ## Threading
/// Marked `@MainActor` - all properties and methods execute on the main thread.
///
/// ## Usage
/// ```swift
/// let viewModel = NotesViewModel(
///     api: notesAPI,
///     store: notesStore,
///     toastCenter: toast,
///     networkStatus: connectivityMonitor
/// )
/// await viewModel.loadTree()
/// await viewModel.selectNote(id: "note-id")
/// await viewModel.createBlankNote()
/// ```
public final class NotesViewModel: ObservableObject {
    @Published public internal(set) var tree: FileTree?
    @Published public internal(set) var archivedTree: FileTree?
    @Published public internal(set) var activeNote: NotePayload?
    @Published public internal(set) var selectedNoteId: String?
    @Published public var searchQuery: String = ""
    @Published public private(set) var searchResults: [FileNode] = []
    @Published public private(set) var isSearching: Bool = false
    @Published public private(set) var isLoadingArchived: Bool = false
    @Published public private(set) var treeLoadState: ContentListLoadState = .idle
    @Published public private(set) var errorMessage: String?

    let api: any NotesProviding
    let store: NotesStore
    let toastCenter: ToastCenter
    let networkStatus: any NetworkStatusProviding
    private let searchTask = ManagedTask()
    private var cancellables = Set<AnyCancellable>()
    var treeMirrorTask: Task<Void, Never>?, archivedTreeMirrorTask: Task<Void, Never>?
    var activeNoteMirrorTask: Task<Void, Never>?
    private var pendingNoteId: String?
    var searchDebounceDelay: TimeInterval = 0.3

    public init(
        api: any NotesProviding,
        store: NotesStore,
        toastCenter: ToastCenter,
        networkStatus: any NetworkStatusProviding
    ) {
        self.api = api
        self.store = store
        self.toastCenter = toastCenter
        self.networkStatus = networkStatus

        store.$tree
            .sink { [weak self] tree in
                self?.scheduleTreeMirror(tree)
            }
            .store(in: &cancellables)

        store.$archivedTree
            .sink { [weak self] tree in
                self?.scheduleArchivedTreeMirror(tree)
            }
            .store(in: &cancellables)

        store.$activeNote
            .sink { [weak self] note in
                self?.scheduleActiveNoteMirror(note)
            }
            .store(in: &cancellables)
    }

    deinit {
        treeMirrorTask?.cancel(); archivedTreeMirrorTask?.cancel(); activeNoteMirrorTask?.cancel()
    }

    func setMirroredTree(_ tree: FileTree?) { self.tree = tree }
    func setMirroredArchivedTree(_ tree: FileTree?) { archivedTree = tree }
    func setMirroredActiveNote(_ note: NotePayload?) { activeNote = note }

    var notesOfflineCapabilityPolicy: OfflineCapabilityPolicy {
        networkStatus.offlineCapabilityPolicy
    }

    public func loadTree() async {
        ContentListReadRecovery.begin(hasVisibleContent: tree != nil)
            .apply(errorMessage: &errorMessage, loadState: &treeLoadState)
        do {
            try await store.loadTree()
            tree = store.tree
            ContentListReadRecovery.success()
                .apply(errorMessage: &errorMessage, loadState: &treeLoadState)
        } catch {
            if let failureTransition = ContentListReadRecovery.failure(
                error: error,
                hasVisibleContent: tree != nil
            ) {
                failureTransition.apply(errorMessage: &errorMessage, loadState: &treeLoadState)
            }
        }
    }

    public func refreshTree(force: Bool = false) async {
        ContentListReadRecovery.begin(hasVisibleContent: tree != nil)
            .apply(errorMessage: &errorMessage, loadState: &treeLoadState)
        do {
            try await store.loadTree(force: force)
            tree = store.tree
            ContentListReadRecovery.success()
                .apply(errorMessage: &errorMessage, loadState: &treeLoadState)
        } catch {
            if let failureTransition = ContentListReadRecovery.failure(
                error: error,
                hasVisibleContent: tree != nil
            ) {
                failureTransition.apply(errorMessage: &errorMessage, loadState: &treeLoadState)
            } else {
                toastCenter.show(message: "Failed to refresh notes")
            }
        }
    }

    public func loadArchivedTree(force: Bool = false) async {
        guard !isLoadingArchived else { return }
        isLoadingArchived = true
        defer { isLoadingArchived = false }
        do {
            try await store.loadArchivedTree(force: force)
            archivedTree = store.archivedTree
        } catch {
            toastCenter.show(message: "Failed to load archived notes")
        }
    }

    public func loadNote(id: String, force: Bool = false) async {
        errorMessage = nil
        selectedNoteId = id
        if activeNote?.id != id {
            store.clearActiveNote()
        }
        if !notesOfflineCapabilityPolicy.canAttemptServerRead, !store.hasCachedNote(id: id) {
            errorMessage = "This note isn't available offline yet."
            pendingNoteId = id
            return
        }
        do {
            try await store.loadNote(id: id, force: force)
            activeNote = store.activeNote
            pendingNoteId = nil
        } catch {
            if activeNote == nil {
                errorMessage = ErrorMapping.message(for: error)
            }
        }
    }

    public func selectNote(id: String) async { await loadNote(id: id) }

    public func clearSelection() {
        selectedNoteId = nil
        pendingNoteId = nil
        activeNote = nil
        store.clearActiveNote()
    }

    public func refreshSelectedNoteIfNeeded() async {
        if let pendingNoteId {
            await loadNote(id: pendingNoteId)
            return
        }
        guard let selectedNoteId, activeNote == nil else { return }
        await loadNote(id: selectedNoteId)
    }

    public func noteNode(id: String) -> FileNode? {
        findNode(id: id, in: tree?.children ?? [])
    }

    public func applyRealtimeEvent(_ payload: RealtimePayload<NoteRealtimeRecord>) async {
        let noteId = payload.record?.id ?? payload.oldRecord?.id
        if payload.eventType == .delete, selectedNoteId == noteId {
            selectedNoteId = nil
        }
        await store.applyRealtimeEvent(payload)
        tree = store.tree
        archivedTree = store.archivedTree
        activeNote = store.activeNote
    }

    public func createBlankNote() async -> NotePayload? {
        AppSentry.recordAction(
            category: "note",
            name: "Started Blank Note",
            data: ["source": "notes_view_model"]
        )
        let request = NoteCreateRequest(
            document: NotesSemanticDocument(
                blocks: [.paragraph([.init(text: "", marks: [])])]
            ),
            plainText: ""
        )
        if notesOfflineCapabilityPolicy.shouldQueueWrites {
            let localID = UUID().uuidString.lowercased()
            do {
                try await store.enqueueCreateNote(localID: localID, request: request)
                let created = store.activeNote
                selectedNoteId = created?.path
                return created
            } catch WriteQueueError.queueFull {
                toastCenter.show(message: "Sync queue full. Review pending changes.")
                return nil
            } catch {
                toastCenter.show(message: "Failed to queue note")
                return nil
            }
        }
        do {
            let created = try await api.createNote(request: request)
            store.applyEditorUpdate(created)
            selectedNoteId = created.path
            await refreshTree(force: true)
            return created
        } catch {
            AppSentry.capture(
                error: error,
                context: [
                    "feature": "notes",
                    "operation": "create_blank_note"
                ]
            )
            toastCenter.show(message: "Failed to create note")
            return nil
        }
    }

    public func createFolder(path: String) async -> Bool {
        let trimmed = path.trimmed
        let normalized = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !normalized.isEmpty else {
            return false
        }
        if notesOfflineCapabilityPolicy.shouldQueueWrites {
            do {
                try await store.enqueueCreateFolder(path: normalized)
                tree = store.tree
                archivedTree = store.archivedTree
                return true
            } catch WriteQueueError.queueFull {
                toastCenter.show(message: "Sync queue full. Review pending changes.")
                return false
            } catch {
                toastCenter.show(message: "Failed to queue folder")
                return false
            }
        }
        do {
            try await api.createFolder(path: normalized)
            await refreshTree(force: true)
            return true
        } catch {
            toastCenter.show(message: "Failed to create folder")
            return false
        }
    }

    public func updateSearch(query: String) {
        searchQuery = query
        searchTask.cancel()
        if query.isBlank {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        let trimmed = query.trimmed
        searchTask.runDebounced(delay: searchDebounceDelay) { [weak self] in
            await self?.performSearch(query: trimmed)
        }
    }

    private func performSearch(query: String) async {
        do {
            let results = try await api.search(query: query, limit: 50)
            errorMessage = nil
            searchResults = results
            isSearching = false
        } catch {
            errorMessage = ErrorMapping.message(for: error)
            searchResults = []
            isSearching = false
        }
    }

    private func findNode(id: String, in nodes: [FileNode]) -> FileNode? {
        for node in nodes {
            if node.path == id {
                return node
            }
            if let children = node.children, let found = findNode(id: id, in: children) {
                return found
            }
        }
        return nil
    }

}
