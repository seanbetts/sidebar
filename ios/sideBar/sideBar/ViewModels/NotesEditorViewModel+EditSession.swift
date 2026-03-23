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
        pendingEditSelectionTarget = target
        pendingEditViewportAnchorY = viewportAnchorY
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
        presentationMode = .read
    }
}
