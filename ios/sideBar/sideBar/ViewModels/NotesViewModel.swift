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
    @Published public private(set) var tree: FileTree?
    @Published public private(set) var archivedTree: FileTree?
    @Published public private(set) var activeNote: NotePayload?
    @Published public private(set) var selectedNoteId: String?
    @Published public var searchQuery: String = ""
    @Published public private(set) var searchResults: [FileNode] = []
    @Published public private(set) var isSearching: Bool = false
    @Published public private(set) var isLoadingArchived: Bool = false
    @Published public private(set) var errorMessage: String?

    private let api: any NotesProviding
    private let store: NotesStore
    private let toastCenter: ToastCenter
    private let networkStatus: any NetworkStatusProviding
    private let searchTask = ManagedTask()
    private var cancellables = Set<AnyCancellable>()
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
                self?.tree = tree
            }
            .store(in: &cancellables)

        store.$archivedTree
            .sink { [weak self] tree in
                self?.archivedTree = tree
            }
            .store(in: &cancellables)

        store.$activeNote
            .sink { [weak self] note in
                self?.scheduleActiveNoteMirror(note)
            }
            .store(in: &cancellables)
    }

    deinit {
        activeNoteMirrorTask?.cancel()
    }

    func setMirroredActiveNote(_ note: NotePayload?) {
        activeNote = note
    }

    public func loadTree() async {
        errorMessage = nil
        do {
            try await store.loadTree()
        } catch {
            if tree == nil {
                errorMessage = ErrorMapping.message(for: error)
            }
        }
    }

    public func refreshTree(force: Bool = false) async {
        do {
            try await store.loadTree(force: force)
        } catch {
            toastCenter.show(message: "Failed to refresh notes")
        }
    }

    public func loadArchivedTree(force: Bool = false) async {
        guard !isLoadingArchived else { return }
        isLoadingArchived = true
        defer { isLoadingArchived = false }
        do {
            try await store.loadArchivedTree(force: force)
        } catch {
            toastCenter.show(message: "Failed to load archived notes")
        }
    }

    public func loadNote(id: String) async {
        errorMessage = nil
        selectedNoteId = id
        store.clearActiveNote()
        if !networkStatus.isNetworkAvailable, !store.hasCachedNote(id: id) {
            errorMessage = "This note isn't available offline yet."
            pendingNoteId = id
            return
        }
        do {
            try await store.loadNote(id: id)
            pendingNoteId = nil
        } catch {
            if activeNote == nil {
                errorMessage = ErrorMapping.message(for: error)
            }
        }
    }

    public func selectNote(id: String) async {
        await loadNote(id: id)
    }

    public func clearSelection() {
        selectedNoteId = nil
        pendingNoteId = nil
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
    }

    public func createBlankNote() async -> NotePayload? {
        AppSentry.recordAction(
            category: "note",
            name: "Started Blank Note",
            data: ["source": "notes_view_model"]
        )
        do {
            let created = try await api.createNote(
                request: NoteCreateRequest(
                    document: NotesSemanticDocument(
                        blocks: [.paragraph([.init(text: "", marks: [])])]
                    ),
                    plainText: ""
                )
            )
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
        do {
            try await api.createFolder(path: normalized)
            await refreshTree(force: true)
            return true
        } catch {
            toastCenter.show(message: "Failed to create folder")
            return false
        }
    }

    public func moveNote(id: String, folder: String) async {
        if !networkStatus.isNetworkAvailable {
            do {
                try await store.enqueueMove(notePath: id, folder: folder)
                if selectedNoteId == id {
                    selectedNoteId = movingPath(id, to: folder)
                }
            } catch WriteQueueError.queueFull {
                toastCenter.show(message: "Sync queue full. Review pending changes.")
            } catch {
                toastCenter.show(message: "Failed to queue move")
            }
            return
        }
        do {
            let updated = try await api.moveNote(id: id, folder: folder)
            store.applyEditorUpdate(updated)
            if selectedNoteId != updated.path {
                selectedNoteId = updated.path
            }
            await refreshTree(force: true)
        } catch {
            toastCenter.show(message: "Failed to move note")
        }
    }

    public func setArchived(id: String, archived: Bool) async {
        if !networkStatus.isNetworkAvailable {
            do {
                try await store.enqueueArchive(notePath: id, archived: archived)
                if archived, selectedNoteId == id {
                    clearSelection()
                }
            } catch WriteQueueError.queueFull {
                toastCenter.show(message: "Sync queue full. Review pending changes.")
            } catch {
                toastCenter.show(message: archived ? "Failed to queue archive" : "Failed to queue unarchive")
            }
            return
        }
        do {
            _ = try await api.archiveNote(id: id, archived: archived)
            if archived, selectedNoteId == id {
                clearSelection()
            }
            await refreshTree(force: true)
        } catch {
            toastCenter.show(message: archived ? "Failed to archive note" : "Failed to unarchive note")
        }
    }

    public func setPinned(id: String, pinned: Bool) async {
        if !networkStatus.isNetworkAvailable {
            do {
                try await store.enqueuePin(notePath: id, pinned: pinned)
            } catch WriteQueueError.queueFull {
                toastCenter.show(message: "Sync queue full. Review pending changes.")
            } catch {
                toastCenter.show(message: pinned ? "Failed to queue pin" : "Failed to queue unpin")
            }
            return
        }
        do {
            _ = try await api.pinNote(id: id, pinned: pinned)
            await refreshTree(force: true)
        } catch {
            toastCenter.show(message: pinned ? "Failed to pin note" : "Failed to unpin note")
        }
    }

    public func deleteNote(id: String) async {
        if !networkStatus.isNetworkAvailable {
            do {
                try await store.enqueueDelete(notePath: id)
                if selectedNoteId == id {
                    clearSelection()
                }
            } catch WriteQueueError.queueFull {
                toastCenter.show(message: "Sync queue full. Review pending changes.")
            } catch {
                toastCenter.show(message: "Failed to queue delete")
            }
            return
        }
        do {
            _ = try await api.deleteNote(id: id)
            if selectedNoteId == id {
                clearSelection()
            }
            store.invalidateNote(id: id)
            await refreshTree(force: true)
        } catch {
            toastCenter.show(message: "Failed to delete note")
        }
    }

    public func updateNoteContent(id: String, document: NotesSemanticDocument) async -> NotePayload? {
        do {
            return try await api.updateNote(id: id, document: document)
        } catch {
            if let urlError = error as? URLError,
               urlError.code == .notConnectedToInternet || urlError.code == .timedOut {
                return nil
            }
            toastCenter.show(message: "Failed to update note")
            return nil
        }
    }

    func applySavedNoteAcknowledgement(serverNote: NotePayload, document: NotesSemanticDocument) {
        let plainText = NotesSemanticDocumentProjection.plainText(from: document)
        let acknowledged = NotePayload(
            id: serverNote.id,
            name: NotesSemanticDocumentProjection.title(from: document),
            document: document,
            documentVersion: document.version,
            plainText: plainText,
            path: serverNote.path,
            modified: serverNote.modified,
            created: serverNote.created
        )
        store.applyEditorUpdate(acknowledged)
    }

    public func applyLocalNoteSnapshot(id: String, document: NotesSemanticDocument) {
        guard let note = activeNote, note.id == id else { return }
        let plainText = NotesSemanticDocumentProjection.plainText(from: document)
        let updated = NotePayload(
            id: note.id,
            name: NotesSemanticDocumentProjection.title(from: document),
            document: document,
            documentVersion: document.version,
            plainText: plainText,
            path: note.path,
            modified: note.modified,
            created: note.created
        )
        store.applyEditorUpdate(updated)
    }

    public func renameFolder(path: String, newName: String) async {
        guard let trimmed = newName.trimmedOrNil else { return }
        let normalized = normalizeFolderPath(path)
        guard !normalized.isEmpty else { return }
        do {
            try await api.renameFolder(oldPath: normalized, newName: trimmed)
            if let selected = selectedNoteId {
                let parent = parentFolderPath(normalized)
                let updatedPrefix = parent.isEmpty ? trimmed : "\(parent)/\(trimmed)"
                // Check if selected note is inside this folder (with proper boundary check)
                let folderPrefix = normalized + "/"
                if selected.hasPrefix(folderPrefix) {
                    let suffix = selected.dropFirst(folderPrefix.count)
                    selectedNoteId = updatedPrefix + "/" + suffix
                } else if selected == normalized {
                    // Edge case: selected path equals the folder path
                    selectedNoteId = updatedPrefix
                }
            }
            await refreshTree(force: true)
        } catch {
            toastCenter.show(message: "Failed to rename folder")
        }
    }

    public func deleteFolder(path: String) async {
        let normalized = normalizeFolderPath(path)
        guard !normalized.isEmpty else { return }
        do {
            try await api.deleteFolder(path: normalized)
            if let selected = selectedNoteId {
                // Check with proper boundary (folder prefix or exact match)
                let folderPrefix = normalized + "/"
                if selected.hasPrefix(folderPrefix) || selected == normalized {
                    clearSelection()
                }
            }
            await refreshTree(force: true)
        } catch {
            toastCenter.show(message: "Failed to delete folder")
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

    private func normalizeFolderPath(_ path: String) -> String {
        let trimmed = path.trimmed
        if trimmed.hasPrefix("folder:") {
            let start = trimmed.index(trimmed.startIndex, offsetBy: 7)
            return String(trimmed[start...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func parentFolderPath(_ path: String) -> String {
        guard let lastSlash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<lastSlash])
    }

    private func movingPath(_ path: String, to folder: String) -> String {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let filename = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
        let normalizedFolder = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let newPath = normalizedFolder.isEmpty ? filename : "\(normalizedFolder)/\(filename)"
        return path.hasPrefix("/") ? "/\(newPath)" : newPath
    }

    /// Refreshes widget data by fetching the latest notes tree
    /// Called by background refresh task to keep widgets up-to-date
    func refreshWidgetData() async {
        do {
            try await store.loadTree(force: true)
        } catch {
            // Silently fail - widget will use cached data
        }
    }
}
