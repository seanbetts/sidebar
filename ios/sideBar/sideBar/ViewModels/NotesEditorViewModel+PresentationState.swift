import Foundation

extension NotesEditorViewModel {
    func cancelPendingPresentationMirrorTasks() {
        NotesTransitionDebugTrace.log("presentation.cancelPendingTasks")
        pendingReadSurfaceViewportMirrorTask?.cancel()
        pendingReadSurfaceViewportMirrorTask = nil
        pendingEditEntryPresentationHoldTask?.cancel()
        pendingEditEntryPresentationHoldTask = nil
        pendingExitEditPresentationTask?.cancel()
        pendingExitEditPresentationTask = nil
    }

    public func completeEditEntryPresentationHold() {
        guard isHoldingReadSurfaceDuringEditEntry else { return }
        NotesTransitionDebugTrace.log(
            "editEntryHold.completeRequested",
            details: [
                "heldTarget=\(String(describing: heldReadSurfaceActivationTarget))",
                "heldAnchorY=\(NotesTransitionDebugTrace.format(heldReadSurfaceViewportAnchorY))"
            ].joined(separator: " ")
        )
        heldReadSurfaceActivationTarget = nil
        heldReadSurfaceViewportAnchorY = nil
        pendingEditEntryPresentationHoldTask?.cancel()
        pendingEditEntryPresentationHoldTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, Task.isCancelled == false else { return }
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard Task.isCancelled == false else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isHoldingReadSurfaceDuringEditEntry = false
                self.pendingEditEntryPresentationHoldTask = nil
                self.scheduleDeferredViewStateObjectWillChange()
                NotesTransitionDebugTrace.log(
                    "editEntryHold.released",
                    details: "presentation=\(String(describing: self.presentationMode))"
                )
            }
        }
    }

    public func setPendingReadSurfaceViewportRestoration(
        offset: CGPoint?,
        target: PendingEditSelectionTarget?,
        viewportAnchorY: CGFloat?
    ) {
        NotesTransitionDebugTrace.log(
            "readViewportRestoration.setPending",
            details: [
                "offset=\(NotesTransitionDebugTrace.format(offset))",
                "target=\(String(describing: target))",
                "anchorY=\(NotesTransitionDebugTrace.format(viewportAnchorY))"
            ].joined(separator: " ")
        )
        pendingReadSurfaceViewportMirrorTask?.cancel()
        pendingReadSurfaceViewportMirrorTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, Task.isCancelled == false else { return }
            self.pendingReadSurfaceViewportOffset = offset
            self.pendingReadSurfaceViewportAnchorTarget = target
            self.pendingReadSurfaceViewportAnchorY = viewportAnchorY
            self.pendingReadSurfaceViewportMirrorTask = nil
            NotesTransitionDebugTrace.log(
                "readViewportRestoration.applied",
                details: [
                    "offset=\(NotesTransitionDebugTrace.format(self.pendingReadSurfaceViewportOffset))",
                    "target=\(String(describing: self.pendingReadSurfaceViewportAnchorTarget))",
                    "anchorY=\(NotesTransitionDebugTrace.format(self.pendingReadSurfaceViewportAnchorY))"
                ].joined(separator: " ")
            )
        }
    }

    public func clearPendingReadSurfaceViewportRestoration() {
        setPendingReadSurfaceViewportRestoration(
            offset: nil,
            target: nil,
            viewportAnchorY: nil
        )
    }

    func scheduleExitEditModePresentation(
        offset: CGPoint?,
        target: PendingEditSelectionTarget?,
        viewportAnchorY: CGFloat?
    ) {
        NotesTransitionDebugTrace.log(
            "editExitPresentation.schedule",
            details: [
                "offset=\(NotesTransitionDebugTrace.format(offset))",
                "target=\(String(describing: target))",
                "anchorY=\(NotesTransitionDebugTrace.format(viewportAnchorY))"
            ].joined(separator: " ")
        )
        pendingReadSurfaceViewportMirrorTask?.cancel()
        pendingEditEntryPresentationHoldTask?.cancel()
        pendingExitEditPresentationTask?.cancel()
        pendingExitEditPresentationTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, Task.isCancelled == false else { return }
            self.pendingReadSurfaceViewportOffset = offset
            self.pendingReadSurfaceViewportAnchorTarget = target
            self.pendingReadSurfaceViewportAnchorY = viewportAnchorY
            self.isHoldingReadSurfaceDuringEditEntry = false
            self.isTransitioningEditExitToRead = false
            self.presentationMode = .read
            self.pendingReadSurfaceViewportMirrorTask = nil
            self.pendingEditEntryPresentationHoldTask = nil
            self.pendingExitEditPresentationTask = nil
            NotesTransitionDebugTrace.log(
                "editExitPresentation.applied",
                details: [
                    "pendingOffset=\(NotesTransitionDebugTrace.format(self.pendingReadSurfaceViewportOffset))",
                    "pendingTarget=\(String(describing: self.pendingReadSurfaceViewportAnchorTarget))",
                    "pendingAnchorY=\(NotesTransitionDebugTrace.format(self.pendingReadSurfaceViewportAnchorY))",
                    "presentation=\(String(describing: self.presentationMode))"
                ].joined(separator: " ")
            )
        }
    }

    func applyReadModeSnapshot(_ document: NotesSemanticDocument) {
        applyEditorSnapshot(
            plainText: NotesSemanticDocumentProjection.plainText(from: document),
            canonicalContent: NotesSemanticDocumentCodec.encode(document) ?? ""
        )
    }

    func applyReadModeSnapshotDeferred(_ document: NotesSemanticDocument) {
        let plainText = NotesSemanticDocumentProjection.plainText(from: document)
        let canonicalContent = NotesSemanticDocumentCodec.encode(document) ?? ""
        Task { @MainActor [weak self] in
            self?.applyEditorSnapshot(
                plainText: plainText,
                canonicalContent: canonicalContent
            )
        }
    }
}
