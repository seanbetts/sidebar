import Foundation
import Combine

// MARK: - NotesEditorViewModel

@MainActor
/// Manages note display state.
public final class NotesEditorViewModel: ObservableObject {
    @Published public private(set) var content: String = ""
    @Published public private(set) var currentNoteId: String?

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
            return
        }
        currentNoteId = note.id
        content = note.content
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
        if await notesViewModel.updateNoteContent(id: noteId, content: markdown) {
            nativeViewModel.markSaved(markdown: markdown)
        }
    }
}
