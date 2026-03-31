#if os(iOS)
import Foundation
import UIKit

@available(iOS 26.0, *)
extension UIKitNoteTextEditorSurface {
    func applyRenderedTextIfNeeded(
        to textView: AccessoryTextView,
        coordinator: Coordinator,
        renderSignature: UIKitNoteTextEditorRenderSignature,
        isProgrammaticRenderUpdate: Bool
    ) {
        guard isProgrammaticRenderUpdate else { return }
        let preservedContentOffset = viewModel.consumeViewportPreservationOnNextProgrammaticRender()
            ? textView.contentOffset : nil
        let attributedText = bridgedAttributedText(from: viewModel.attributedContent)
        coordinator.isApplyingProgrammaticText = true
        textView.textStorage.setAttributedString(attributedText)
        coordinator.isApplyingProgrammaticText = false
        textView.invalidateCodeBlockBackgroundLayout()
        if let preservedContentOffset {
            textView.layoutIfNeeded()
            textView.setContentOffset(
                Self.clampedContentOffset(preservedContentOffset, for: textView),
                animated: false
            )
        }
        coordinator.lastAppliedRenderSignature = renderSignature
    }

    func applySelectionIfNeeded(
        to textView: AccessoryTextView,
        coordinator: Coordinator,
        selectedRange: NSRange
    ) {
        let displaySelectedRange = SelectableNoteReadView.editorDisplaySelectedRange(
            in: viewModel.currentPersistenceSnapshot().document,
            logicalSelectedRange: selectedRange
        )
        guard textView.selectedRange != displaySelectedRange else { return }
        coordinator.isApplyingProgrammaticSelection = true
        textView.selectedRange = displaySelectedRange
        coordinator.isApplyingProgrammaticSelection = false
    }
}
#endif
