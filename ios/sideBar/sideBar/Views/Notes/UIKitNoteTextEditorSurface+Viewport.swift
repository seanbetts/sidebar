#if os(iOS)
import SwiftUI
import UIKit

@available(iOS 26.0, *)
extension UIKitNoteTextEditorSurface {
    func preservedViewportOffsetIfNeeded(
        for textView: UITextView,
        selectedRange: NSRange,
        preserveAcrossSelectionChange: Bool
    ) -> CGPoint? {
        if let accessoryTextView = textView as? AccessoryTextView,
           accessoryTextView.hasPendingUnappliedInitialViewportOffset {
            return nil
        }
        guard textView.window != nil else { return nil }
        guard preserveAcrossSelectionChange else { return nil }
        return textView.contentOffset
    }

    func restoreViewportOffsetIfNeeded(
        _ offset: CGPoint,
        for textView: UITextView,
        selectedRange: NSRange
    ) {
        guard textView.selectedRange == selectedRange else { return }
        textView.layoutIfNeeded()
        textView.setContentOffset(Self.clampedContentOffset(offset, for: textView), animated: false)
        (textView as? AccessoryTextView)?.recordStableSelectionViewport()
    }

    static func clampedContentOffset(
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
