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
        isFloatingFormattingBarVisible
    }

    var isFloatingFormattingBarVisible: Bool {
        #if os(iOS)
        formattingBarPresentation == .floatingTopTrailing
            && !editorViewModel.isHoldingReadSurfaceDuringEditEntry
        #else
        formattingBarPresentation == .floatingTopTrailing
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
        if editorViewModel.presentationMode == .edit,
           editorViewModel.currentNoteId == activeNote.id,
           let document = NotesSemanticDocumentCodec.decode(editorViewModel.canonicalContent) {
            return document
        }
        return activeNote.document
    }

    func activateReadSurfaceEditing(at target: NotesEditorViewModel.PendingEditSelectionTarget) {
        activateReadSurfaceEditing(at: target, viewportAnchorY: nil)
    }

    func activateReadSurfaceEditing(
        at target: NotesEditorViewModel.PendingEditSelectionTarget,
        viewportAnchorY: CGFloat?
    ) {
        guard currentUnsupportedContent == nil else { return }
        #if os(iOS)
        NotesIOSDebugTrace.log(
            "NotesDetailView.activateReadSurfaceEditing",
            extras: [
                "isShowingEditorSurface": "\(isShowingEditorSurface)",
                "isShowingReadSurface": "\(isShowingReadSurface)",
                "target": "\(target)",
                "viewportAnchorY": viewportAnchorY.map { String(format: "%.2f", $0) } ?? "nil"
            ]
        )
        #endif
        #if os(iOS)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        #endif
        editorViewModel.enterEditMode(at: target, viewportAnchorY: viewportAnchorY)
    }

    func handleReadViewportOffsetChange(_ offset: CGPoint) {
        #if os(iOS)
        if editorViewModel.isHoldingReadSurfaceDuringEditEntry {
            return
        }
        NotesIOSDebugTrace.log(
            "NotesDetailView.handleReadViewportOffsetChange",
            extras: [
                "offset": "{x:\(String(format: "%.2f", offset.x)),y:\(String(format: "%.2f", offset.y))}"
            ]
        )
        #endif
        let hasPendingReadRestoration =
            editorViewModel.pendingReadSurfaceViewportOffset != nil
            || editorViewModel.pendingReadSurfaceViewportAnchorTarget != nil
            || editorViewModel.pendingReadSurfaceViewportAnchorY != nil
        if hasPendingReadRestoration {
            return
        }
        if isHoldingEditorSurfaceDuringReadExit {
            guard pendingReadExitHoldTargetOffset != nil else {
                return
            }
            if let targetOffset = pendingReadExitHoldTargetOffset {
                let matchesExitTarget =
                    abs(offset.x - targetOffset.x) <= 1
                    && abs(offset.y - targetOffset.y) <= 2
                if matchesExitTarget == false {
                    return
                }
            } else if hasPendingReadRestoration {
                return
            }
            isHoldingEditorSurfaceDuringReadExit = false
            pendingReadExitHoldTargetOffset = nil
        }
        editorViewModel.heldReadSurfaceViewportOffset = offset
    }

    func handleReadInitialViewportRestorationApplied() {
        if let restoredOffset = editorViewModel.pendingReadSurfaceViewportOffset {
            editorViewModel.heldReadSurfaceViewportOffset = restoredOffset
        }
        editorViewModel.clearPendingReadSurfaceViewportRestoration()
        if isHoldingEditorSurfaceDuringReadExit {
            isHoldingEditorSurfaceDuringReadExit = false
            pendingReadExitHoldTargetOffset = nil
        }
    }

    func handleCloseShortcut(editedDocument: NotesSemanticDocument? = nil) {
        guard viewModel.activeNote != nil else { return }
        let hasAttachedNativeEditor: Bool
        if #available(iOS 26.0, macOS 26.0, *) {
            hasAttachedNativeEditor = editorViewModel.attachedNativeEditorViewModel != nil
        } else {
            hasAttachedNativeEditor = false
        }
        guard editedDocument != nil || editorViewModel.isEditingNote || hasAttachedNativeEditor else {
            requestCloseNote()
            return
        }
        let document = editedDocument ?? editorViewModel.currentSemanticDocumentSnapshot()
        #if os(macOS)
        if let noteId = viewModel.activeNote?.id {
            viewModel.applyLocalNoteSnapshot(id: noteId, document: document)
        }
        editorViewModel.applyReadModeSnapshotDeferred(document)
        editorViewModel.exitEditModeToRead()
        Task {
            await editorViewModel.saveDocumentSnapshotIfNeeded(document, force: true)
        }
        #else
        if let noteId = viewModel.activeNote?.id {
            viewModel.applyLocalNoteSnapshot(id: noteId, document: document)
        }
        editorViewModel.applyReadModeSnapshotDeferred(document)
        isHoldingEditorSurfaceDuringReadExit = true
        pendingReadExitHoldTargetOffset = nil
        Task {
            await editorViewModel.saveIfNeeded()
            if #available(iOS 26.0, *) {
                editorViewModel.captureLiveEditorViewportSnapshotFromAttachedTextView()
            }
            editorViewModel.exitEditModeToRead()
        }
        #endif
    }

    func handleEscapeKey(_ document: NotesSemanticDocument) {
        handleCloseShortcut(editedDocument: document)
    }

    func handleShortcutActionEvent(
        _ event: ShortcutActionEvent?,
        workspacePane: WorkspacePane
    ) {
        guard let event,
              event.matches(section: .notes, workspacePane: workspacePane) else { return }
        switch event.action {
        case .closeItem:
            handleCloseShortcut()
        case .deleteItem:
            guard viewModel.activeNote != nil else { return }
            isDeleteAlertPresented = true
        case .archiveItem:
            archiveActiveNote()
        default:
            break
        }
    }
}
