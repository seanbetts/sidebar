import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

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
        liveEditorViewportOffset = nil
        liveEditorSelectionTarget = nil
        liveEditorSelectionViewportAnchorY = nil
        pendingReadViewportRestoration = nil
        clearPendingReadSurfaceViewportRestoration()
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

    public func recordLiveEditorViewportOffset(_ offset: CGPoint) {
        liveEditorViewportOffset = offset
    }

    public func recordLiveEditorViewportSnapshot(
        offset: CGPoint,
        selectedUTF16Range: NSRange,
        selectionViewportAnchorY: CGFloat?
    ) {
        liveEditorViewportOffset = offset
        if selectedUTF16Range.location != NSNotFound {
            liveEditorSelectionTarget = .characterOffset(selectedUTF16Range.location)
        } else {
            liveEditorSelectionTarget = nil
        }
        liveEditorSelectionViewportAnchorY = selectionViewportAnchorY
    }

    #if os(iOS)
    @available(iOS 26.0, *)
    public func attachNativeEditorTextView(_ textView: UITextView) {
        nativeEditorTextView = textView
    }

    @available(iOS 26.0, *)
    public func detachNativeEditorTextView(_ textView: UITextView) {
        guard nativeEditorTextView === textView else { return }
        nativeEditorTextView = nil
    }

    @available(iOS 26.0, *)
    public func captureLiveEditorViewportSnapshotFromAttachedTextView() {
        guard let textView = nativeEditorTextView as? UIKitNoteTextEditorSurface.AccessoryTextView,
              let nativeEditorViewModel else {
            return
        }
        let selectedUTF16Range = nativeEditorViewModel.utf16SelectedRange(
            in: nativeEditorViewModel.attributedContent
        )
        recordLiveEditorViewportSnapshot(
            offset: textView.contentOffset,
            selectedUTF16Range: selectedUTF16Range,
            selectionViewportAnchorY: textView.viewportAnchorY(forSelectedRange: selectedUTF16Range)
        )
    }
    #endif

    func consumePendingReadViewportRestoration() -> PendingReadViewportRestoration? {
        defer { pendingReadViewportRestoration = nil }
        return pendingReadViewportRestoration
    }

    public func exitEditModeToRead() {
        pendingEditSelectionTarget = nil
        pendingEditViewportAnchorY = nil
        #if os(iOS)
        if #available(iOS 26.0, *),
           let textView = nativeEditorTextView as? UIKitNoteTextEditorSurface.AccessoryTextView,
           let nativeEditorViewModel {
            liveEditorViewportOffset = textView.contentOffset
            let selectedUTF16Range = nativeEditorViewModel.utf16SelectedRange(
                in: nativeEditorViewModel.attributedContent
            )
            if selectedUTF16Range.location != NSNotFound {
                liveEditorSelectionTarget = .characterOffset(selectedUTF16Range.location)
                liveEditorSelectionViewportAnchorY = textView.viewportAnchorY(
                    forSelectedRange: selectedUTF16Range
                )
            } else {
                liveEditorSelectionTarget = nil
                liveEditorSelectionViewportAnchorY = nil
            }
        }
        #endif
        let restoration = PendingReadViewportRestoration(
            offset: liveEditorViewportOffset,
            target: nil,
            viewportAnchorY: nil
        )
        pendingReadViewportRestoration = restoration
        setPendingReadSurfaceViewportRestoration(
            offset: restoration.offset,
            target: restoration.target,
            viewportAnchorY: restoration.viewportAnchorY
        )
        debugLastExitReadViewportRestoration = restoration
        #if os(iOS)
        if #available(iOS 26.0, *) {
            NotesIOSDebugTrace.log(
                "NotesEditorViewModel.exitEditModeToRead",
                extras: [
                    "offset": liveEditorViewportOffset.map {
                        "{x:\(String(format: "%.2f", $0.x)),y:\(String(format: "%.2f", $0.y))}"
                    } ?? "nil",
                    "target": liveEditorSelectionTarget.map { "\($0)" } ?? "nil",
                    "viewportAnchorY": liveEditorSelectionViewportAnchorY.map {
                        String(format: "%.2f", $0)
                    } ?? "nil"
                ]
            )
        }
        #endif
        liveEditorViewportOffset = nil
        liveEditorSelectionTarget = nil
        liveEditorSelectionViewportAnchorY = nil
        isHoldingReadSurfaceDuringEditEntry = false
        heldReadSurfaceActivationTarget = nil
        heldReadSurfaceViewportAnchorY = nil
        presentationMode = .read
    }
}
