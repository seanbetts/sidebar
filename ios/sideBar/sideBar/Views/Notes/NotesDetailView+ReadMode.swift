import SwiftUI

extension NotesDetailView {
    var isShowingReadSurface: Bool {
        viewModel.activeNote != nil && editorViewModel.presentationMode == .read
    }

    var isShowingEditorSurface: Bool {
        viewModel.activeNote != nil && editorViewModel.presentationMode == .edit
    }

    var isFormattingToolbarVisible: Bool {
        isShowingEditorSurface
    }

    var currentReadDocument: NotesSemanticDocument {
        guard let activeNote = viewModel.activeNote else {
            return NotesSemanticDocumentProjection.document(fromPlainText: "")
        }
        if editorViewModel.currentNoteId == activeNote.id,
           let document = NotesSemanticDocumentCodec.decode(editorViewModel.canonicalContent) {
            return document
        }
        return activeNote.document
    }

    func activateReadSurfaceEditing() {
        editorViewModel.enterEditMode()
    }

    func handleCloseShortcut(editedDocument: NotesSemanticDocument? = nil) {
        guard viewModel.activeNote != nil else { return }
        guard editorViewModel.isEditingNote else {
            requestCloseNote()
            return
        }
        let document = editedDocument ?? editorViewModel.currentSemanticDocumentSnapshot()
        if let noteId = viewModel.activeNote?.id {
            viewModel.applyLocalNoteSnapshot(id: noteId, document: document)
        }
        Task {
            await editorViewModel.saveIfNeeded()
            editorViewModel.exitEditModeToRead()
        }
    }

    func handleEscapeKey(_ document: NotesSemanticDocument) {
        handleCloseShortcut(editedDocument: document)
    }
}
