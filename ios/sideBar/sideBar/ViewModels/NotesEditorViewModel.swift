import Foundation
import Combine

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
    @Published private(set) var conflict: NoteSyncConflict?

    private let notesViewModel: NotesViewModel
    private let draftStorage: DraftStorage
    private let writeQueue: WriteQueue
    @available(iOS 26.0, macOS 26.0, *)
    private weak var nativeEditorViewModel: NativeMarkdownEditorViewModel?
    private var cancellables = Set<AnyCancellable>()

    init(
        notesViewModel: NotesViewModel,
        draftStorage: DraftStorage,
        writeQueue: WriteQueue
    ) {
        self.notesViewModel = notesViewModel
        self.draftStorage = draftStorage
        self.writeQueue = writeQueue

        notesViewModel.$activeNote
            .sink { [weak self] note in
                self?.handleNoteUpdate(note)
            }
            .store(in: &cancellables)
    }

    private func handleNoteUpdate(_ note: NotePayload?) {
        guard let note else {
            currentNoteId = nil
            content = ""
            isDirty = false
            isSaving = false
            lastSavedAt = nil
            saveErrorMessage = nil
            conflict = nil
            return
        }
        currentNoteId = note.id
        content = note.content
        isDirty = false
        isSaving = false
        lastSavedAt = nil
        saveErrorMessage = nil
        conflict = nil
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
                return
            }
            content = draft.content
            isDirty = true
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
        let markdown = nativeViewModel.currentMarkdown()
        guard markdown != content else { return }
        isSaving = true
        saveErrorMessage = nil
        do {
            try draftStorage.saveDraft(entityType: "note", entityId: noteId, content: markdown)
        } catch {
            saveErrorMessage = "Failed to save draft"
        }
        let saved = await notesViewModel.updateNoteContent(id: noteId, content: markdown)
        isSaving = false
        if saved {
            try? draftStorage.markSynced(entityType: "note", entityId: noteId)
            nativeViewModel.markSaved(markdown: markdown)
            isDirty = false
            lastSavedAt = Date()
        } else {
            saveErrorMessage = "Failed to save note"
            let payload = NoteUpdatePayload(content: markdown)
            try? writeQueue.enqueue(
                operation: .update,
                entityType: .note,
                entityId: noteId,
                payload: payload
            )
        }
    }

    public func saveIfNeeded() async {
        guard isDirty, !isSaving else { return }
        if #available(iOS 26.0, macOS 26.0, *) {
            guard let nativeViewModel = nativeEditorViewModel else { return }
            await syncFromNativeEditor(nativeViewModel)
        }
    }

    public func resolveConflictKeepLocal() async {
        guard let conflict else { return }
        content = conflict.localContent
        isDirty = true
        try? draftStorage.saveDraft(
            entityType: "note",
            entityId: conflict.noteId,
            content: conflict.localContent
        )
        self.conflict = nil
    }

    public func resolveConflictKeepServer() async {
        guard let conflict else { return }
        content = conflict.serverContent
        isDirty = false
        try? draftStorage.deleteDraft(entityType: "note", entityId: conflict.noteId)
        self.conflict = nil
    }

    public func resolveConflictKeepBoth() async {
        guard let conflict else { return }
        let folder = folderPath(from: conflict.notePath)
        let copyTitle = copyTitle(from: conflict.noteName)
        let localContent = conflict.localContent
        content = conflict.serverContent
        isDirty = false
        try? draftStorage.deleteDraft(entityType: "note", entityId: conflict.noteId)
        self.conflict = nil

        guard let created = await notesViewModel.createNote(title: copyTitle, folder: folder) else {
            saveErrorMessage = "Failed to create copy"
            return
        }
        _ = await notesViewModel.updateNoteContent(id: created.id, content: localContent)
    }

    public func setDirty(_ dirty: Bool) {
        isDirty = dirty
    }

    public func setReadOnly(_ readOnly: Bool) {
        isReadOnly = readOnly
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
