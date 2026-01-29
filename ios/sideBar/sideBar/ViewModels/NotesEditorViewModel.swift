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

    private let notesViewModel: NotesViewModel
    private let draftStorage: DraftStorage
    private let writeQueue: WriteQueue
    @available(iOS 26.0, macOS 26.0, *)
    private weak var nativeEditorViewModel: NativeMarkdownEditorViewModel?
    private var cancellables = Set<AnyCancellable>()

    public init(
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
            return
        }
        currentNoteId = note.id
        content = note.content
        isDirty = false
        isSaving = false
        lastSavedAt = nil
        saveErrorMessage = nil
        Task { [weak self] in
            await self?.applyDraftIfAvailable(for: note)
        }
    }

    private func applyDraftIfAvailable(for note: NotePayload) async {
        do {
            guard let draft = try await draftStorage.getDraft(entityType: "note", entityId: note.id) else { return }
            guard draft.syncedAt == nil else { return }
            let serverDate = note.modified.map { Date(timeIntervalSince1970: $0) }
            if let serverDate, draft.savedAt < serverDate {
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
            try await draftStorage.saveDraft(entityType: "note", entityId: noteId, content: markdown)
        } catch {
            saveErrorMessage = "Failed to save draft"
        }
        let saved = await notesViewModel.updateNoteContent(id: noteId, content: markdown)
        isSaving = false
        if saved {
            try? await draftStorage.markSynced(entityType: "note", entityId: noteId)
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
