#if os(iOS)
import UIKit

@available(iOS 26.0, *)
extension UIKitNoteTextEditorSurface.AccessoryTextView {
    var hasPendingUnappliedInitialViewportOffset: Bool {
        pendingInitialViewportOffset != nil && hasAppliedPendingInitialViewportOffset == false
    }

    func updatePendingInitialViewportOffset(_ offset: CGPoint?) {
        guard let offset else {
            guard initialViewportVerificationPassesRemaining == 0 else { return }
            pendingInitialViewportOffset = nil
            return
        }
        pendingInitialViewportOffset = offset
    }

    func updateKeyboardObservation() {
        removeKeyboardObservers()
        guard window != nil else {
            keyboardFrameInScreen = nil
            updateViewportInsets()
            return
        }

        let center = NotificationCenter.default
        keyboardObservers = [
            center.addObserver(
                forName: UIResponder.keyboardWillChangeFrameNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleKeyboardNotification(notification)
            },
            center.addObserver(
                forName: UIResponder.keyboardWillHideNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.keyboardFrameInScreen = nil
                self?.updateViewportInsets()
            }
        ]
        updateViewportInsets()
    }

    func removeKeyboardObservers() {
        let center = NotificationCenter.default
        keyboardObservers.forEach(center.removeObserver)
        keyboardObservers.removeAll()
    }

    func handleKeyboardNotification(_ notification: Notification) {
        guard let frameValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else {
            return
        }
        keyboardFrameInScreen = frameValue.cgRectValue
        updateViewportInsets()
    }

    func updateViewportInsets() {
        let keyboardInset = UIKitNoteTextEditorSurface.resolvedBottomViewportInset(
            textViewBounds: bounds,
            keyboardFrameInView: resolvedKeyboardFrameInView(),
            accessoryHeight: resolvedAccessoryHeight()
        )
        let bottomInset = keyboardInset + Self.baseTextContainerInsets.bottom
        let previousBottomInset = contentInset.bottom
        contentInset.bottom = bottomInset
        var indicatorInsets = verticalScrollIndicatorInsets
        indicatorInsets.bottom = bottomInset
        verticalScrollIndicatorInsets = indicatorInsets

        guard abs(previousBottomInset - bottomInset) > 0.5 else { return }
        scrollCurrentSelectionIntoView()
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

    func resolvedKeyboardFrameInView() -> CGRect? {
        guard let keyboardFrameInScreen,
              let window else { return nil }
        let keyboardFrameInWindow = window.convert(keyboardFrameInScreen, from: nil)
        return convert(keyboardFrameInWindow, from: window)
    }

    func resolvedAccessoryHeight() -> CGFloat {
        guard formattingAccessoryView != nil, isFirstResponder else { return 0 }
        return formattingAccessoryView?.bounds.height ?? 0
    }

    func applyPendingInitialViewportOffsetIfNeeded() {
        guard hasAppliedPendingInitialViewportOffset == false,
              let pendingInitialViewportOffset,
              window != nil else { return }
        guard bounds.height > 0, contentSize.height > 0 else { return }
        layoutIfNeeded()
        guard applyInitialViewportOffset(pendingInitialViewportOffset) else {
            scheduleInitialViewportVerificationIfNeeded(after: 0.02)
            return
        }
        hasAppliedPendingInitialViewportOffset = true
        guard isCurrentSelectionVisible() else {
            initialViewportVerificationPassesRemaining = 0
            self.pendingInitialViewportOffset = nil
            scrollCurrentSelectionIntoView()
            scheduleSelectionVisibilityRetryBurst()
            return
        }
        scheduleInitialViewportVerificationIfNeeded()
        scheduleSelectionVisibilityRetryBurst()
    }

    func scheduleInitialViewportVerificationIfNeeded(after delay: TimeInterval = 0) {
        guard isInitialViewportVerificationScheduled == false,
              initialViewportVerificationPassesRemaining > 0,
              let pendingInitialViewportOffset else { return }
        isInitialViewportVerificationScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.isInitialViewportVerificationScheduled = false
            self.verifyInitialViewportOffsetIfNeeded(pendingInitialViewportOffset)
        }
    }

    func verifyInitialViewportOffsetIfNeeded(_ offset: CGPoint) {
        guard pendingInitialViewportOffset == offset else { return }
        let resolution = resolveInitialViewportOffset(offset)
        guard case .resolved(let resolvedOffset) = resolution else {
            if initialViewportVerificationPassesRemaining > 0 {
                initialViewportVerificationPassesRemaining -= 1
                scheduleInitialViewportVerificationIfNeeded(after: 0.02)
            }
            return
        }
        let isStable =
            abs(contentOffset.x - resolvedOffset.x) <= 0.5 &&
            abs(contentOffset.y - resolvedOffset.y) <= 0.5
        guard isStable == false else {
            initialViewportVerificationPassesRemaining = 0
            pendingInitialViewportOffset = nil
            scrollCurrentSelectionIntoView()
            scheduleSelectionVisibilityRetryBurst()
            return
        }

        guard initialViewportVerificationPassesRemaining > 0 else { return }
        initialViewportVerificationPassesRemaining -= 1
        guard applyInitialViewportOffset(offset) else { return }
        hasAppliedPendingInitialViewportOffset = true
        scheduleInitialViewportVerificationIfNeeded()
    }

    @discardableResult
    private func applyInitialViewportOffset(_ offset: CGPoint) -> Bool {
        guard case .resolved(let resolvedOffset) = resolveInitialViewportOffset(offset) else { return false }
        setContentOffset(resolvedOffset, animated: false)
        return true
    }

    private enum InitialViewportResolution {
        case notReady
        case unresolved
        case resolved(CGPoint)
    }

    private func resolveInitialViewportOffset(_ offset: CGPoint) -> InitialViewportResolution {
        guard bounds.height > 0, contentSize.height > 0 else { return .notReady }
        layoutIfNeeded()
        let resolvedOffset = UIKitNoteTextEditorSurface.clampedContentOffset(offset, for: self)
        guard resolvedOffset.x + 0.5 >= offset.x,
              resolvedOffset.y + 0.5 >= offset.y else { return .unresolved }
        return .resolved(resolvedOffset)
    }

    private func scheduleSelectionVisibilityRetryBurst() {
        for delay in [0.0, 0.01, 0.05] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.window != nil else { return }
                self.scrollCurrentSelectionIntoView()
            }
        }
    }

    func scrollCurrentSelectionIntoView() {
        guard selectedRange.location != NSNotFound else { return }
        guard let selectionRect = selectionRectInContentCoordinates() else {
            scrollRangeToVisible(selectedRange)
            return
        }
        let visibleViewport = visibleViewportRect()
        if isSelectionRectVisible(selectionRect, in: visibleViewport) {
            return
        }

        var targetOffset = contentOffset
        let verticalMargin = max(Self.baseTextContainerInsets.top, 12)

        if selectionRect.minY < visibleViewport.minY {
            targetOffset.y -= (visibleViewport.minY - selectionRect.minY) + verticalMargin
        } else if selectionRect.maxY > visibleViewport.maxY {
            targetOffset.y += (selectionRect.maxY - visibleViewport.maxY) + verticalMargin
        }

        setContentOffset(
            UIKitNoteTextEditorSurface.clampedContentOffset(targetOffset, for: self),
            animated: false
        )
        layoutIfNeeded()

        let targetRect = selectionRect.insetBy(dx: 0, dy: -verticalMargin)
        if visibleViewportRect().intersects(targetRect) == false {
            scrollRectToVisible(targetRect, animated: false)
        }
    }

    func isCurrentSelectionVisible() -> Bool {
        guard let selectionRect = selectionRectInContentCoordinates() else { return false }
        return isSelectionRectVisible(selectionRect, in: visibleViewportRect())
    }

    func selectionRectInContentCoordinates() -> CGRect? {
        if let textRange = selectedTextRange {
            if textRange.isEmpty {
                return caretRect(for: textRange.start)
            }

            let rect = firstRect(for: textRange)
            if rect.isNull == false, rect.isEmpty == false {
                return rect
            }
        }

        guard selectedRange.location != NSNotFound else { return nil }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: selectedRange, actualCharacterRange: nil)
        return layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
    }

    func visibleViewportRect() -> CGRect {
        bounds.inset(by: adjustedContentInset)
    }

    private func isSelectionRectVisible(_ selectionRect: CGRect, in viewport: CGRect) -> Bool {
        viewport.contains(selectionRect.insetBy(dx: 0, dy: -1))
    }
}
#endif
