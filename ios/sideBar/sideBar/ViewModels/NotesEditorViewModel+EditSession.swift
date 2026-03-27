import Foundation
import SwiftUI

extension NotesEditorViewModel {
    public func saveIfNeeded() async {
        guard !isSaving else { return }
        if #available(iOS 26.0, macOS 26.0, *) {
            guard let nativeViewModel = nativeEditorViewModel else {
                guard isDirty else { return }
                return
            }
            let snapshot = nativeViewModel.currentPersistenceSnapshot()
            let hasNativeDelta = nativeViewModel.hasUnsavedChanges ||
                snapshot.canonicalContent != canonicalContent ||
                snapshot.plainText != content
            guard hasNativeDelta || isDirty else { return }
            await syncFromNativeEditor(nativeViewModel)
            return
        }
        guard isDirty else { return }
    }

    public func currentPlainTextSnapshot(fallback: String = "") -> String {
        if #available(iOS 26.0, macOS 26.0, *), let nativeEditorViewModel {
            let plainText = nativeEditorViewModel.currentPersistenceSnapshot().plainText
            return plainText.isEmpty ? fallback : plainText
        }
        return content.isEmpty ? fallback : content
    }

    public func currentSemanticDocumentSnapshot() -> NotesSemanticDocument {
        if #available(iOS 26.0, macOS 26.0, *) {
            if let nativeEditorViewModel {
                return nativeEditorViewModel.currentPersistenceSnapshot().document
            }
        }
        if let document = NotesSemanticDocumentCodec.decode(canonicalContent) { return document }
        return NotesSemanticDocumentProjection.document(fromPlainText: content)
    }

    public var isEditingNote: Bool { presentationMode == .edit }

    public func enterEditMode() { enterEditMode(at: .start) }

    public func enterEditMode(
        at target: PendingEditSelectionTarget,
        viewportAnchorY: CGFloat? = nil
    ) {
        guard currentNoteId != nil, unsupportedContent == nil else { return }
        #if os(iOS)
        if #available(iOS 26.0, *) {
            NotesIOSDebugTrace.log(
                "NotesEditorViewModel.enterEditMode",
                extras: [
                    "target": "\(target)",
                    "viewportAnchorY": viewportAnchorY.map { String(format: "%.2f", $0) } ?? "nil",
                    "currentNoteId": currentNoteId ?? "nil"
                ]
            )
        }
        #endif
        pendingEditSelectionTarget = target
        pendingEditViewportAnchorY = viewportAnchorY
        #if os(iOS)
        isHoldingReadSurfaceDuringEditEntry = viewportAnchorY != nil
        heldReadSurfaceActivationTarget = viewportAnchorY == nil ? nil : target
        heldReadSurfaceViewportAnchorY = viewportAnchorY
        #else
        isHoldingReadSurfaceDuringEditEntry = false
        heldReadSurfaceActivationTarget = nil
        heldReadSurfaceViewportAnchorY = nil
        #endif
        presentationMode = .edit
    }

    func pendingEditSelectionTargetForCurrentEditSession() -> PendingEditSelectionTarget? {
        pendingEditSelectionTarget
    }

    public func consumePendingEditSelectionTarget() -> PendingEditSelectionTarget? {
        defer { pendingEditSelectionTarget = nil }
        return pendingEditSelectionTarget
    }

    public func consumePendingEditViewportAnchorY() -> CGFloat? {
        defer { pendingEditViewportAnchorY = nil }
        return pendingEditViewportAnchorY
    }

    var debugPendingEditViewportOffset: CGPoint? { nil }

    public func exitEditModeToRead() {
        pendingEditSelectionTarget = nil
        pendingEditViewportAnchorY = nil
        isHoldingReadSurfaceDuringEditEntry = false
        heldReadSurfaceActivationTarget = nil
        heldReadSurfaceViewportAnchorY = nil
        presentationMode = .read
    }
}
