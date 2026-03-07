import Combine
import Foundation

@MainActor
/// Runtime boundary for notes list/editor state and note-context shaping.
public final class NotesRuntime: ObservableObject {
    /// Notes list and selection coordinator.
    public let viewModel: NotesViewModel
    /// Notes editor coordinator.
    public let editorViewModel: NotesEditorViewModel

    private var cancellables = Set<AnyCancellable>()

    public init(
        viewModel: NotesViewModel,
        editorViewModel: NotesEditorViewModel
    ) {
        self.viewModel = viewModel
        self.editorViewModel = editorViewModel

        viewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        editorViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    /// Active note payload when available.
    public var activeNote: NotePayload? {
        viewModel.activeNote
    }

    /// Selected note identifier.
    public var selectedNoteId: String? {
        viewModel.selectedNoteId
    }

    /// Build canonical open-note context for prompt requests.
    public func openNoteContext() -> [String: Any]? {
        guard let activeNote else { return nil }
        let noteText = editorViewModel.currentPlainTextSnapshot(
            fallback: activeNote.plainText
        )
        return [
            "id": activeNote.id,
            "title": activeNote.name,
            "path": activeNote.path,
            "plain_text": noteText
        ]
    }
}
