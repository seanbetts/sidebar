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
    private var cancellables = Set<AnyCancellable>()

    public init(notesViewModel: NotesViewModel) {
        self.notesViewModel = notesViewModel

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
    }

    @available(iOS 26.0, macOS 26.0, *)
    public func makeNativeEditorViewModel() -> NativeMarkdownEditorViewModel {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.loadMarkdown(content)
        return viewModel
    }

    @available(iOS 26.0, macOS 26.0, *)
    public func syncFromNativeEditor(_ nativeViewModel: NativeMarkdownEditorViewModel) async {
        guard let noteId = currentNoteId else { return }
        let markdown = nativeViewModel.currentMarkdown()
        guard markdown != content else { return }
        isSaving = true
        saveErrorMessage = nil
        let saved = await notesViewModel.updateNoteContent(id: noteId, content: markdown)
        isSaving = false
        if saved {
            nativeViewModel.markSaved(markdown: markdown)
            isDirty = false
            lastSavedAt = Date()
        } else {
            saveErrorMessage = "Failed to save note"
        }
    }

    public func setDirty(_ dirty: Bool) {
        isDirty = dirty
    }

    public func setReadOnly(_ readOnly: Bool) {
        isReadOnly = readOnly
    }
}
