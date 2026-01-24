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
}
