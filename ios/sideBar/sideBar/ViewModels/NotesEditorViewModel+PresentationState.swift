import Foundation

extension NotesEditorViewModel {
    public func completeEditEntryPresentationHold() {
        guard isHoldingReadSurfaceDuringEditEntry else { return }
        isHoldingReadSurfaceDuringEditEntry = false
        heldReadSurfaceActivationTarget = nil
        heldReadSurfaceViewportAnchorY = nil
    }

    func applyReadModeSnapshot(_ document: NotesSemanticDocument) {
        applyEditorSnapshot(
            plainText: NotesSemanticDocumentProjection.plainText(from: document),
            canonicalContent: NotesSemanticDocumentCodec.encode(document) ?? ""
        )
    }
}
