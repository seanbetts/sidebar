#if os(iOS)
import SwiftUI
import UIKit

@available(iOS 26.0, *)
extension UIKitNoteTextEditorSurface {
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
