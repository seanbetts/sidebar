#if os(iOS)
import UIKit

@available(iOS 26.0, *)
extension UIKitNoteTextEditorSurface.AccessoryTextView {
    private static let selectionViewportTolerance: CGFloat = 2

    func updateViewportInsets() {
        let bottomInset = Self.baseTextContainerInsets.bottom
        contentInset.bottom = bottomInset
        var indicatorInsets = verticalScrollIndicatorInsets
        indicatorInsets.bottom = bottomInset
        verticalScrollIndicatorInsets = indicatorInsets
    }

    func updateTextContainerInsets() {
        let extraHorizontalInset = max((bounds.width - maxReadableContentWidth) / 2, 0)
        let resolvedInsets = UIEdgeInsets(
            top: Self.baseTextContainerInsets.top,
            left: Self.baseTextContainerInsets.left + extraHorizontalInset,
            bottom: Self.baseTextContainerInsets.bottom,
            right: Self.baseTextContainerInsets.right + extraHorizontalInset
        )
        guard textContainerInset != resolvedInsets else { return }
        textContainerInset = resolvedInsets
    }

    func scrollCurrentSelectionIntoView() {
        guard selectedRange.location != NSNotFound else { return }
        guard let selectionRect = selectionRectInContentCoordinates(for: selectedRange) else {
            scrollRangeToVisible(selectedRange)
            return
        }
        scrollSelectionRectIntoView(selectionRect)
    }

    func isCurrentSelectionVisible() -> Bool {
        guard let selectionRect = selectionRectInContentCoordinates(for: selectedRange) else { return false }
        return isSelectionRectVisible(selectionRect, in: visibleViewportRect())
    }

    func isCurrentSelectionIntersectingViewport() -> Bool {
        guard let selectionRect = selectionRectInContentCoordinates(for: selectedRange) else { return false }
        return isSelectionRectIntersectingViewport(selectionRect, in: visibleViewportRect())
    }

    func selectionRectInContentCoordinates() -> CGRect? {
        selectionRectInContentCoordinates(for: selectedRange)
    }

    func selectionRectInContentCoordinates(for range: NSRange) -> CGRect? {
        guard range.location != NSNotFound else { return nil }
        if range.length == 0,
           let position = position(from: beginningOfDocument, offset: range.location) {
            return caretRect(for: position)
        }

        if let textRange = textRange(for: range) {
            let rect = firstRect(for: textRange)
            if rect.isNull == false, rect.isEmpty == false {
                return rect
            }
        }
        return nil
    }

    func visibleViewportRect() -> CGRect {
        bounds.inset(by: adjustedContentInset)
    }

    private func isSelectionRectVisible(_ selectionRect: CGRect, in viewport: CGRect) -> Bool {
        viewport.contains(
            selectionRect.insetBy(dx: 0, dy: -Self.selectionViewportTolerance)
        )
    }

    private func isSelectionRectIntersectingViewport(_ selectionRect: CGRect, in viewport: CGRect) -> Bool {
        selectionRect.maxY >= viewport.minY - Self.selectionViewportTolerance &&
            selectionRect.minY <= viewport.maxY + Self.selectionViewportTolerance
    }

    private func scrollSelectionRectIntoView(_ selectionRect: CGRect) {
        let visibleViewport = visibleViewportRect()
        if isSelectionRectVisible(selectionRect, in: visibleViewport) {
            return
        }

        var targetOffset = contentOffset
        if selectionRect.minY < visibleViewport.minY {
            targetOffset.y -= visibleViewport.minY - selectionRect.minY
        } else if selectionRect.maxY > visibleViewport.maxY {
            targetOffset.y += selectionRect.maxY - visibleViewport.maxY
        }

        setContentOffset(
            UIKitNoteTextEditorSurface.clampedContentOffset(targetOffset, for: self),
            animated: false
        )
        layoutIfNeeded()

        if isCurrentSelectionVisible() == false {
            scrollRectToVisible(selectionRect, animated: false)
        }
    }

    private func textRange(for range: NSRange) -> UITextRange? {
        guard let start = position(from: beginningOfDocument, offset: range.location) else {
            return nil
        }
        guard let end = position(from: start, offset: range.length) else {
            return nil
        }
        return textRange(from: start, to: end)
    }
}
#endif
