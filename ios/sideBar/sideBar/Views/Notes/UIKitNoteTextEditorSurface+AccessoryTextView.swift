#if os(iOS)
import UIKit

@available(iOS 26.0, *)
extension UIKitNoteTextEditorSurface.AccessoryTextView {
    var hasPendingUnappliedInitialViewportOffset: Bool {
        pendingInitialViewportOffset != nil && hasAppliedPendingInitialViewportOffset == false
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
        let bottomInset = UIKitNoteTextEditorSurface.resolvedBottomViewportInset(
            textViewBounds: bounds,
            keyboardFrameInView: resolvedKeyboardFrameInView(),
            accessoryHeight: resolvedAccessoryHeight()
        )
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
        guard applyInitialViewportOffset(pendingInitialViewportOffset) else { return }
        hasAppliedPendingInitialViewportOffset = true
    }

    func applyDeferredInitialViewportOffsetIfNeeded(_ offset: CGPoint) {
        guard window != nil else { return }
        guard applyInitialViewportOffset(offset) else { return }
        hasAppliedPendingInitialViewportOffset = true
    }

    @discardableResult
    private func applyInitialViewportOffset(_ offset: CGPoint) -> Bool {
        guard bounds.height > 0, contentSize.height > 0 else { return false }
        layoutIfNeeded()
        let resolvedOffset = UIKitNoteTextEditorSurface.clampedContentOffset(offset, for: self)
        guard resolvedOffset.x + 0.5 >= offset.x,
              resolvedOffset.y + 0.5 >= offset.y else { return false }
        setContentOffset(resolvedOffset, animated: false)
        return true
    }
}
#endif
