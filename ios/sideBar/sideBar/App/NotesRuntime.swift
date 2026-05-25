import Combine
import Foundation

/// Runtime boundary for notes list/editor state and note-context shaping.
@MainActor public final class NotesRuntime: ObservableObject {
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

    /// Creates a blank note, then enters edit mode once the editor has hydrated it.
    @discardableResult
    public func createBlankNoteAndEnterEditMode() async -> NotePayload? {
        guard let createdNote = await viewModel.createBlankNote() else { return nil }

        let hydrationAttempts = 10
        for _ in 0..<hydrationAttempts {
            guard editorViewModel.currentNoteId != createdNote.id else {
                editorViewModel.enterEditMode()
                return createdNote
            }
            await Task.yield()
        }

        if editorViewModel.currentNoteId == createdNote.id {
            editorViewModel.enterEditMode()
        }
        return createdNote
    }

    /// Build canonical open-note context for prompt requests.
    public func openNoteContext() -> [String: Any]? {
        guard let activeNote else { return nil }
        let noteText = editorViewModel.currentPlainTextSnapshot(
            fallback: activeNote.plainText
        )
        let semanticDocument = editorViewModel.currentSemanticDocumentSnapshot()
        return [
            "id": activeNote.id,
            "title": activeNote.name,
            "path": activeNote.path,
            "plain_text": noteText,
            "document": semanticDocument.asJSONObject() ?? [:]
        ]
    }
}

private extension NotesSemanticDocument {
    func asJSONObject() -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(self),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        return dictionary
    }
}
