#if os(iOS)
import SwiftUI
import UIKit

@available(iOS 26.0, *)
extension UIKitNoteTextEditorSurface {
    static func resolvedBottomViewportInset(
        textViewBounds: CGRect,
        keyboardFrameInView: CGRect?,
        accessoryHeight: CGFloat
    ) -> CGFloat {
        guard let keyboardFrameInView,
              keyboardFrameInView.intersects(textViewBounds) else {
            return 0
        }

        let overlap = max(textViewBounds.maxY - keyboardFrameInView.minY, 0)
        return max(overlap + accessoryHeight, 0)
    }

    func preservedViewportOffsetIfNeeded(
        for textView: UITextView,
        selectedRange: NSRange
    ) -> CGPoint? {
        guard textView.isFirstResponder else { return nil }
        guard textView.selectedRange == selectedRange else { return nil }
        return textView.contentOffset
    }

    func restoreViewportOffsetIfNeeded(
        _ offset: CGPoint,
        for textView: UITextView,
        selectedRange: NSRange
    ) {
        guard textView.selectedRange == selectedRange else { return }
        textView.layoutIfNeeded()
        textView.setContentOffset(clampedContentOffset(offset, for: textView), animated: false)
    }

    func clampedContentOffset(
        _ offset: CGPoint,
        for textView: UITextView
    ) -> CGPoint {
        let adjustedInsets = textView.adjustedContentInset
        let minX = -adjustedInsets.left
        let minY = -adjustedInsets.top
        let maxX = max(
            minX,
            textView.contentSize.width + adjustedInsets.right - textView.bounds.width
        )
        let maxY = max(
            minY,
            textView.contentSize.height + adjustedInsets.bottom - textView.bounds.height
        )
        return CGPoint(
            x: min(max(offset.x, minX), maxX),
            y: min(max(offset.y, minY), maxY)
        )
    }
}
#endif
