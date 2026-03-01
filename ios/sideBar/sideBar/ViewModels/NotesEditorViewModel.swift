import Foundation
import Combine
import OSLog

// MARK: - NotesEditorViewModel

@MainActor
/// Manages note display state.
public final class NotesEditorViewModel: ObservableObject {
    @Published public private(set) var content: String = ""
    @Published public private(set) var currentNoteId: String?
    @Published public private(set) var isDirty: Bool = false
    @Published public private(set) var isSaving: Bool = false
    @Published public private(set) var lastSavedAt: Date?
    @Published public private(set) var saveErrorMessage: String?
    @Published public private(set) var isReadOnly: Bool = true
    @Published public private(set) var isQueuedForSync: Bool = false
    @Published private(set) var conflict: NoteSyncConflict?

    private let notesViewModel: NotesViewModel
    private let draftStorage: DraftStorage
    private let writeQueue: WriteQueue
    private let networkStatus: any NetworkStatusProviding
    private let logger = Logger(subsystem: "sideBar", category: "AttributedEditorMigration")
    @available(iOS 26.0, macOS 26.0, *)
    private weak var nativeEditorViewModel: NativeMarkdownEditorViewModel?
    private var syncRequestedWhileSaving = false
    private var cancellables = Set<AnyCancellable>()

    init(
        notesViewModel: NotesViewModel,
        draftStorage: DraftStorage,
        writeQueue: WriteQueue,
        networkStatus: any NetworkStatusProviding
    ) {
        self.notesViewModel = notesViewModel
        self.draftStorage = draftStorage
        self.writeQueue = writeQueue
        self.networkStatus = networkStatus

        notesViewModel.$activeNote
            .sink { [weak self] note in
                self?.handleNoteUpdate(note)
            }
            .store(in: &cancellables)
    }

    private func handleNoteUpdate(_ note: NotePayload?) {
        let previousNoteId = currentNoteId
        guard let note else {
            currentNoteId = nil
            content = ""
            isDirty = false
            isSaving = false
            lastSavedAt = nil
            saveErrorMessage = nil
            isQueuedForSync = false
            conflict = nil
            syncRequestedWhileSaving = false
            return
        }
        let isSameNote = previousNoteId == note.id
        if isSameNote, isSaving {
            // Avoid clobbering pending local edits while an in-flight save publishes
            // the same note back through NotesStore.
            return
        }
        currentNoteId = note.id
        content = note.content
        syncNativeEditorContent(note.content)
        isDirty = false
        isSaving = false
        lastSavedAt = nil
        saveErrorMessage = nil
        isQueuedForSync = false
        conflict = nil
        if !isSameNote {
            syncRequestedWhileSaving = false
        }
        Task { [weak self] in
            await self?.applyDraftIfAvailable(for: note)
        }
    }

    private func applyDraftIfAvailable(for note: NotePayload) async {
        do {
            guard let draft = try draftStorage.getDraft(entityType: "note", entityId: note.id) else { return }
            guard draft.syncedAt == nil else { return }
            let serverDate = note.modified.map { Date(timeIntervalSince1970: $0) }
            if shouldPresentNoteConflict(
                localContent: draft.content,
                localDate: draft.savedAt,
                serverContent: note.content,
                serverDate: serverDate
            ) {
                conflict = NoteSyncConflict(
                    id: UUID(),
                    noteId: note.id,
                    noteName: note.name,
                    notePath: note.path,
                    localContent: draft.content,
                    serverContent: note.content,
                    localDate: draft.savedAt,
                    serverDate: serverDate ?? Date()
                )
                content = note.content
                isDirty = false
                return
            }
            if draft.content == note.content {
                try? draftStorage.markSynced(entityType: "note", entityId: note.id)
                isQueuedForSync = false
                return
            }
            content = draft.content
            syncNativeEditorContent(draft.content)
            isDirty = true
            isQueuedForSync = true
        } catch {
            saveErrorMessage = "Failed to load draft"
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    public func makeNativeEditorViewModel() -> NativeMarkdownEditorViewModel {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.loadMarkdown(content)
        return viewModel
    }

    @available(iOS 26.0, macOS 26.0, *)
    public func attachNativeEditor(_ nativeViewModel: NativeMarkdownEditorViewModel) {
        nativeEditorViewModel = nativeViewModel
    }

    @available(iOS 26.0, macOS 26.0, *)
    public func detachNativeEditor(_ nativeViewModel: NativeMarkdownEditorViewModel) {
        if nativeEditorViewModel === nativeViewModel {
            nativeEditorViewModel = nil
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    public func syncFromNativeEditor(_ nativeViewModel: NativeMarkdownEditorViewModel) async {
        guard let noteId = currentNoteId else { return }
        if isSaving {
            syncRequestedWhileSaving = true
            return
        }

        let markdown = nativeViewModel.currentMarkdown()
        guard markdown != content else {
            syncRequestedWhileSaving = false
            return
        }

        isSaving = true
        saveErrorMessage = nil
        do {
            try draftStorage.saveDraft(entityType: "note", entityId: noteId, content: markdown)
        } catch {
            saveErrorMessage = "Failed to save draft"
        }

        if !networkStatus.isNetworkAvailable {
            let payload = NoteUpdatePayload(content: markdown)
            let snapshot = makeServerSnapshot(noteId: noteId)
            do {
                try await writeQueue.enqueue(
                    operation: .update,
                    entityType: .note,
                    entityId: noteId,
                    payload: payload,
                    serverSnapshot: snapshot
                )
            } catch WriteQueueError.queueFull {
                saveErrorMessage = "Sync queue full. Review pending changes."
            } catch {
                saveErrorMessage = "Failed to queue changes"
            }
            nativeViewModel.markSaved(markdown: markdown)
            content = markdown
            isSaving = false
            isDirty = false
            isQueuedForSync = true
            await syncFromNativeEditorIfRequested(nativeViewModel)
            return
        }

        let saved = await notesViewModel.updateNoteContent(id: noteId, content: markdown)
        isSaving = false
        if saved {
            try? draftStorage.markSynced(entityType: "note", entityId: noteId)
            nativeViewModel.markSaved(markdown: markdown)
            content = markdown
            isDirty = false
            lastSavedAt = Date()
            isQueuedForSync = false
        } else {
            saveErrorMessage = "Failed to save note"
            let payload = NoteUpdatePayload(content: markdown)
            let snapshot = makeServerSnapshot(noteId: noteId)
            do {
                try await writeQueue.enqueue(
                    operation: .update,
                    entityType: .note,
                    entityId: noteId,
                    payload: payload,
                    serverSnapshot: snapshot
                )
            } catch WriteQueueError.queueFull {
                saveErrorMessage = "Sync queue full. Review pending changes."
            } catch {
                saveErrorMessage = "Failed to queue changes"
            }
            isQueuedForSync = true
        }
        await syncFromNativeEditorIfRequested(nativeViewModel)
    }

    public func saveIfNeeded() async {
        guard isDirty, !isSaving else { return }
        if #available(iOS 26.0, macOS 26.0, *) {
            guard let nativeViewModel = nativeEditorViewModel else { return }
            await syncFromNativeEditor(nativeViewModel)
        }
    }

    public func currentMarkdownSnapshot(fallback: String = "") -> String {
        if #available(iOS 26.0, macOS 26.0, *) {
            if let nativeEditorViewModel {
                let markdown = nativeEditorViewModel.currentMarkdown()
                return markdown.isEmpty ? fallback : markdown
            }
            let source = content.isEmpty ? fallback : content
            guard !source.isEmpty else { return "" }
            return canonicalMarkdownSnapshot(from: source)
        }
        return content.isEmpty ? fallback : content
    }

    public func resolveConflictKeepLocal() async {
        guard let conflict else { return }
        let canonicalLocalContent = canonicalMarkdownForPersistence(conflict.localContent)
        content = canonicalLocalContent
        isDirty = true
        isQueuedForSync = true
        try? draftStorage.saveDraft(
            entityType: "note",
            entityId: conflict.noteId,
            content: canonicalLocalContent
        )
        self.conflict = nil
    }

    public func resolveConflictKeepServer() async {
        guard let conflict else { return }
        content = conflict.serverContent
        isDirty = false
        try? draftStorage.deleteDraft(entityType: "note", entityId: conflict.noteId)
        isQueuedForSync = false
        self.conflict = nil
    }

    public func resolveConflictKeepBoth() async {
        guard let conflict else { return }
        let folder = folderPath(from: conflict.notePath)
        let copyTitle = copyTitle(from: conflict.noteName)
        let localContent = canonicalMarkdownForPersistence(conflict.localContent)
        content = conflict.serverContent
        isDirty = false
        try? draftStorage.deleteDraft(entityType: "note", entityId: conflict.noteId)
        isQueuedForSync = false
        self.conflict = nil

        guard let created = await notesViewModel.createNote(title: copyTitle, folder: folder) else {
            saveErrorMessage = "Failed to create copy"
            return
        }
        _ = await notesViewModel.updateNoteContent(id: created.id, content: localContent)
        await notesViewModel.selectNote(id: conflict.notePath)
    }

    public func setDirty(_ dirty: Bool) {
        isDirty = dirty
    }

    public func setReadOnly(_ readOnly: Bool) {
        isReadOnly = readOnly
    }

    private func syncNativeEditorContent(_ markdown: String) {
        if #available(iOS 26.0, macOS 26.0, *) {
            guard let nativeEditorViewModel else { return }
            guard nativeEditorViewModel.currentMarkdown() != markdown else { return }
            nativeEditorViewModel.loadMarkdown(markdown)
        }
    }

    private func canonicalMarkdownForPersistence(_ markdown: String) -> String {
        if #available(iOS 26.0, macOS 26.0, *) {
            return canonicalMarkdownSnapshot(from: markdown)
        }
        return markdown
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func canonicalMarkdownSnapshot(from markdown: String) -> String {
        let nativeViewModel = NativeMarkdownEditorViewModel()
        nativeViewModel.loadMarkdown(markdown)
        return nativeViewModel.currentMarkdown()
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func syncFromNativeEditorIfRequested(_ nativeViewModel: NativeMarkdownEditorViewModel) async {
        guard syncRequestedWhileSaving else { return }
        syncRequestedWhileSaving = false
        await syncFromNativeEditor(nativeViewModel)
    }

    private func makeServerSnapshot(noteId: String) -> ServerSnapshot? {
        guard let note = notesViewModel.activeNote, note.id == noteId else {
            return nil
        }
        let node = notesViewModel.noteNode(id: note.path)
        let snapshot = NoteSnapshot(
            modified: note.modified,
            name: note.name,
            path: note.path,
            pinned: node?.pinned,
            pinnedOrder: node?.pinnedOrder,
            archived: node?.archived
        )
        return ServerSnapshot(
            entityType: .note,
            entityId: noteId,
            capturedAt: Date(),
            payload: .note(snapshot)
        )
    }
}

private struct NoteUpdatePayload: Codable {
    let content: String
}

private func folderPath(from notePath: String) -> String? {
    let trimmed = notePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let parts = trimmed.split(separator: "/")
    guard parts.count > 1 else { return nil }
    return parts.dropLast().joined(separator: "/")
}

private func copyTitle(from noteName: String) -> String {
    if noteName.hasSuffix(".md") {
        let base = String(noteName.dropLast(3))
        return "\(base) (Offline Copy)"
    }
    return "\(noteName) (Offline Copy)"
}
