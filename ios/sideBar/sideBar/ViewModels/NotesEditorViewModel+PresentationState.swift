import Foundation

extension NotesEditorViewModel {
    public func completeEditEntryPresentationHold() {
        guard isHoldingReadSurfaceDuringEditEntry else { return }
        isHoldingReadSurfaceDuringEditEntry = false
        heldReadSurfaceActivationTarget = nil
        heldReadSurfaceViewportAnchorY = nil
    }

    public func setPendingReadSurfaceViewportRestoration(
        offset: CGPoint?,
        target: PendingEditSelectionTarget?,
        viewportAnchorY: CGFloat?
    ) {
        pendingReadSurfaceViewportOffset = offset
        pendingReadSurfaceViewportAnchorTarget = target
        pendingReadSurfaceViewportAnchorY = viewportAnchorY
    }

    public func clearPendingReadSurfaceViewportRestoration() {
        pendingReadSurfaceViewportOffset = nil
        pendingReadSurfaceViewportAnchorTarget = nil
        pendingReadSurfaceViewportAnchorY = nil
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
