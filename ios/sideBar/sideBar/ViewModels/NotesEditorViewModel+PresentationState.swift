import Foundation

extension NotesEditorViewModel {
    func cancelPendingPresentationMirrorTasks() {
        pendingReadSurfaceViewportMirrorTask?.cancel()
        pendingReadSurfaceViewportMirrorTask = nil
        pendingEditEntryPresentationHoldTask?.cancel()
        pendingEditEntryPresentationHoldTask = nil
        pendingExitEditPresentationTask?.cancel()
        pendingExitEditPresentationTask = nil
    }

    public func completeEditEntryPresentationHold() {
        guard isHoldingReadSurfaceDuringEditEntry else { return }
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
            }
        }
    }

    public func setPendingReadSurfaceViewportRestoration(
        offset: CGPoint?,
        target: PendingEditSelectionTarget?,
        viewportAnchorY: CGFloat?
    ) {
        pendingReadSurfaceViewportMirrorTask?.cancel()
        pendingReadSurfaceViewportMirrorTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, Task.isCancelled == false else { return }
            self.pendingReadSurfaceViewportOffset = offset
            self.pendingReadSurfaceViewportAnchorTarget = target
            self.pendingReadSurfaceViewportAnchorY = viewportAnchorY
            self.pendingReadSurfaceViewportMirrorTask = nil
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
        pendingReadSurfaceViewportMirrorTask?.cancel()
        pendingEditEntryPresentationHoldTask?.cancel()
        pendingExitEditPresentationTask?.cancel()
        pendingExitEditPresentationTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, Task.isCancelled == false else { return }
            self.isHoldingEditorSurfaceDuringReadExit = true
            self.pendingReadExitHoldTargetOffset = offset
            self.readSurfacePresentationGeneration &+= 1
            self.pendingReadSurfaceViewportOffset = offset
            self.pendingReadSurfaceViewportAnchorTarget = target
            self.pendingReadSurfaceViewportAnchorY = viewportAnchorY
            self.isHoldingReadSurfaceDuringEditEntry = false
            self.isTransitioningEditExitToRead = false
            self.presentationMode = .read
            self.pendingReadSurfaceViewportMirrorTask = nil
            self.pendingEditEntryPresentationHoldTask = nil
            self.pendingExitEditPresentationTask = nil
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
