import SwiftUI

extension NotesDetailView {
    var currentUnsupportedContent: NotesUnsupportedContent? {
        guard let activeNote = viewModel.activeNote else { return nil }
        if editorViewModel.currentNoteId == activeNote.id {
            return editorViewModel.unsupportedContent
                ?? NotesUnsupportedContent.detect(in: activeNote.document)
        }
        return NotesUnsupportedContent.detect(in: activeNote.document)
    }

    var isShowingUnsupportedContentPlaceholder: Bool {
        viewModel.activeNote != nil && currentUnsupportedContent != nil
    }

    var isShowingReadSurface: Bool {
        viewModel.activeNote != nil &&
            currentUnsupportedContent == nil &&
            editorViewModel.presentationMode == .read
    }

    var isShowingEditorSurface: Bool {
        viewModel.activeNote != nil &&
            currentUnsupportedContent == nil &&
            editorViewModel.presentationMode == .edit
    }

    var isFormattingToolbarVisible: Bool {
        isShowingEditorSurface
    }

    var isCustomFormattingBarVisible: Bool {
        #if os(iOS)
        isFloatingFormattingBarVisible
        #else
        false
        #endif
    }

    var isFloatingFormattingBarVisible: Bool {
        #if os(iOS)
        formattingBarPresentation == .floatingTopTrailing
        #else
        false
        #endif
    }

    var unsupportedContentPlaceholderTitle: String {
        NotesUnsupportedContent.placeholderTitle
    }

    var unsupportedContentPlaceholderMessage: String? {
        currentUnsupportedContent?.placeholderMessage
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

    func activateReadSurfaceEditing(at target: NotesEditorViewModel.PendingEditSelectionTarget) {
        guard currentUnsupportedContent == nil else { return }
        editorViewModel.enterEditMode(at: target)
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
