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
        NotesTransitionDebugTrace.log(
            "readSurface.activateEditing",
            details: [
                "target=\(String(describing: target))",
                "viewportAnchorY=\(NotesTransitionDebugTrace.format(viewportAnchorY))",
                "heldReadOffset=\(NotesTransitionDebugTrace.format(editorViewModel.heldReadSurfaceViewportOffset))"
            ].joined(separator: " ")
        )
        #if os(iOS)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        DispatchQueue.main.async {
            editorViewModel.enterEditMode(at: target, viewportAnchorY: viewportAnchorY)
        }
        #else
        editorViewModel.enterEditMode(at: target, viewportAnchorY: viewportAnchorY)
        #endif
    }

    func handleReadSurfaceChecklistToggle(blockIndex: Int, itemIndex: Int) {
        Task {
            await editorViewModel.toggleChecklistItemInReadMode(
                blockIndex: blockIndex,
                itemIndex: itemIndex
            )
        }
    }

    func handleReadViewportOffsetChange(_ offset: CGPoint) {
        NotesTransitionDebugTrace.log(
            "readSurface.viewportOffsetChanged",
            details: [
                "offset=\(NotesTransitionDebugTrace.format(offset))",
                "pendingOffset=\(NotesTransitionDebugTrace.format(editorViewModel.pendingReadSurfaceViewportOffset))",
                "holdEditorDuringExit=\(isHoldingEditorSurfaceDuringReadExit)"
            ].joined(separator: " ")
        )
        #if os(iOS)
        if editorViewModel.isHoldingReadSurfaceDuringEditEntry {
            return
        }
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
            NotesTransitionDebugTrace.log("readSurface.exitHoldReleasedFromViewportMatch")
        }
        editorViewModel.heldReadSurfaceViewportOffset = offset
    }

    func handleReadInitialViewportRestorationApplied() {
        let restoredOffset = editorViewModel.pendingReadSurfaceViewportOffset
        NotesTransitionDebugTrace.log(
            "readSurface.initialViewportRestorationApplied",
            details: "offset=\(NotesTransitionDebugTrace.format(restoredOffset))"
        )
        DispatchQueue.main.async {
            if let restoredOffset {
                editorViewModel.heldReadSurfaceViewportOffset = restoredOffset
            }
            editorViewModel.clearPendingReadSurfaceViewportRestoration()
            if isHoldingEditorSurfaceDuringReadExit {
                isHoldingEditorSurfaceDuringReadExit = false
                pendingReadExitHoldTargetOffset = nil
            }
        }
    }

    func handleCloseShortcut(editedDocument: NotesSemanticDocument? = nil) {
        guard viewModel.activeNote != nil else { return }
        NotesTransitionDebugTrace.log(
            "detail.closeShortcut",
            details: [
                "hasEditedDocument=\(editedDocument != nil)",
                "isEditing=\(editorViewModel.isEditingNote)",
                "presentation=\(String(describing: editorViewModel.presentationMode))"
            ].joined(separator: " ")
        )
        guard editedDocument != nil || editorViewModel.isEditingNote else {
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
        let capturedViewportBeforeDismissal: Bool
        if #available(iOS 26.0, *) {
            capturedViewportBeforeDismissal =
                editorViewModel.captureLiveEditorViewportSnapshotFromAttachedTextView()
        } else {
            capturedViewportBeforeDismissal = false
        }
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        if #available(iOS 26.0, *) {
            _ = editorViewModel.nativeEditorTextView?.resignFirstResponder()
        }
        editorViewModel.exitEditModeToRead(
            captureAttachedTextViewSnapshot: capturedViewportBeforeDismissal == false
        )
        Task {
            await editorViewModel.saveIfNeeded()
        }
        #endif
    }

    func handleEscapeKey(_ document: NotesSemanticDocument) {
        guard editorViewModel.presentationMode == .edit else {
            handleCloseShortcut()
            return
        }
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
