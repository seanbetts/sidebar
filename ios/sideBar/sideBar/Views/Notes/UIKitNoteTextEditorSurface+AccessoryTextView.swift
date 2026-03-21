#if os(iOS)
import UIKit

@available(iOS 26.0, *)
extension UIKitNoteTextEditorSurface.AccessoryTextView {
    private enum SelectionMovementDirection {
        case up
        case down
        case none
    }

    private static let selectionViewportTolerance: CGFloat = 2

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

    func recordStableSelectionViewport() {
        lastStableSelectionRange = selectedRange
        lastStableViewportOffset = contentOffset
    }

    override open func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        markUpcomingSelectionChangeAsDirectTouch()
        super.touchesBegan(touches, with: event)
    }

    func markUpcomingSelectionChangeAsDirectTouch() {
        directTouchSelectionChangeDeadline = CACurrentMediaTime() + 0.2
    }

    func consumeDirectTouchSelectionChange() -> Bool {
        let isDirectTouchSelectionChange = CACurrentMediaTime() <= directTouchSelectionChangeDeadline
        directTouchSelectionChangeDeadline = 0
        return isDirectTouchSelectionChange
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
        guard isCurrentSelectionIntersectingViewport() == false else {
            recordStableSelectionViewport()
            scheduleInitialViewportVerificationIfNeeded()
            return
        }
        guard isCurrentSelectionVisible() else {
            initialViewportVerificationPassesRemaining = 0
            self.pendingInitialViewportOffset = nil
            scrollCurrentSelectionIntoView()
            recordStableSelectionViewport()
            return
        }
        recordStableSelectionViewport()
        scheduleInitialViewportVerificationIfNeeded()
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
            if isCurrentSelectionIntersectingViewport() == false {
                scrollCurrentSelectionIntoView()
            }
            recordStableSelectionViewport()
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

    func cancelDeferredViewportAdjustment() {
        selectionChangeAdjustmentGeneration += 1
        deferredViewportRestorationGeneration += 1
        initialViewportVerificationPassesRemaining = 0
        pendingInitialViewportOffset = nil
    }

    func scheduleDeferredViewportRestoration(
        to offset: CGPoint,
        selectedRange: NSRange
    ) {
        deferredViewportRestorationGeneration += 1
        let generation = deferredViewportRestorationGeneration
        for delay in [0.0, 0.01, 0.05, 0.1] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self,
                      self.window != nil,
                      self.deferredViewportRestorationGeneration == generation,
                      self.selectedRange == selectedRange else {
                    return
                }
                self.layoutIfNeeded()
                self.setContentOffset(
                    UIKitNoteTextEditorSurface.clampedContentOffset(offset, for: self),
                    animated: false
                )
            }
        }
    }

    func scheduleSelectionChangeVisibilityAdjustment(
        from previousSelectedRange: NSRange,
        isDirectTouchSelectionChange: Bool
    ) {
        selectionChangeAdjustmentGeneration += 1
        let generation = selectionChangeAdjustmentGeneration
        let baselineContentOffset = lastStableSelectionRange == previousSelectedRange ?
            lastStableViewportOffset : contentOffset
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            guard let self,
                  self.window != nil,
                  self.selectionChangeAdjustmentGeneration == generation else { return }
            self.scrollSelectionChangeIntoView(
                from: previousSelectedRange,
                baselineContentOffset: baselineContentOffset,
                isDirectTouchSelectionChange: isDirectTouchSelectionChange
            )
        }
    }

    func scrollSelectionChangeIntoView(
        from previousSelectedRange: NSRange,
        baselineContentOffset: CGPoint,
        isDirectTouchSelectionChange: Bool
    ) {
        guard selectedRange.location != NSNotFound else { return }
        guard let selectionRect = selectionRectInContentCoordinates(for: selectedRange) else { return }

        let movementDirection = selectionMovementDirection(
            from: previousSelectedRange,
            to: selectedRange
        )
        let visibleViewport = visibleViewportRect()
        let baselineViewportOffset = UIKitNoteTextEditorSurface.clampedContentOffset(
            baselineContentOffset,
            for: self
        )
        if isDirectTouchSelectionChange,
           isSelectionRectIntersectingViewport(selectionRect, in: visibleViewport) {
            restoreStableViewportOffsetIfNeeded(
                baselineViewportOffset,
                for: movementDirection,
                selectionRect: selectionRect,
                visibleViewport: visibleViewport,
                forceRestore: true
            )
            recordStableSelectionViewport()
            return
        }
        if isSelectionRectVisible(selectionRect, in: visibleViewport) {
            restoreStableViewportOffsetIfNeeded(
                baselineViewportOffset,
                for: movementDirection,
                selectionRect: selectionRect,
                visibleViewport: visibleViewport,
                forceRestore: true
            )
            recordStableSelectionViewport()
            return
        }

        switch movementDirection {
        case .up:
            guard selectionRect.minY < visibleViewport.minY - Self.selectionViewportTolerance else {
                restoreStableViewportOffsetIfNeeded(
                    baselineViewportOffset,
                    for: movementDirection,
                    selectionRect: selectionRect,
                    visibleViewport: visibleViewport,
                    forceRestore: true
                )
                recordStableSelectionViewport()
                return
            }
        case .down:
            guard selectionRect.maxY > visibleViewport.maxY + Self.selectionViewportTolerance else {
                restoreStableViewportOffsetIfNeeded(
                    baselineViewportOffset,
                    for: movementDirection,
                    selectionRect: selectionRect,
                    visibleViewport: visibleViewport,
                    forceRestore: true
                )
                recordStableSelectionViewport()
                return
            }
        case .none:
            guard selectionRect.maxY < visibleViewport.minY - Self.selectionViewportTolerance ||
                    selectionRect.minY > visibleViewport.maxY + Self.selectionViewportTolerance else {
                restoreStableViewportOffsetIfNeeded(
                    baselineViewportOffset,
                    for: movementDirection,
                    selectionRect: selectionRect,
                    visibleViewport: visibleViewport,
                    forceRestore: true
                )
                recordStableSelectionViewport()
                return
            }
        }

        scrollSelectionRectIntoView(selectionRect)
        recordStableSelectionViewport()
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

    private func restoreStableViewportOffsetIfNeeded(
        _ baselineViewportOffset: CGPoint,
        for movementDirection: SelectionMovementDirection,
        selectionRect: CGRect,
        visibleViewport: CGRect,
        forceRestore: Bool = false
    ) {
        if forceRestore {
            if abs(contentOffset.y - baselineViewportOffset.y) > 0.5 {
                setContentOffset(baselineViewportOffset, animated: false)
            }
            scheduleDeferredViewportRestoration(
                to: baselineViewportOffset,
                selectedRange: selectedRange
            )
            return
        }

        guard abs(contentOffset.y - baselineViewportOffset.y) > 0.5 else { return }
        let shouldRestore: Bool
        switch movementDirection {
        case .up:
            shouldRestore = contentOffset.y > baselineViewportOffset.y
        case .down:
            shouldRestore = contentOffset.y < baselineViewportOffset.y
        case .none:
            shouldRestore = isSelectionRectIntersectingViewport(selectionRect, in: visibleViewport)
        }
        guard shouldRestore else { return }
        setContentOffset(baselineViewportOffset, animated: false)
        scheduleDeferredViewportRestoration(
            to: baselineViewportOffset,
            selectedRange: selectedRange
        )
    }

    private func selectionMovementDirection(
        from previousRange: NSRange,
        to newRange: NSRange
    ) -> SelectionMovementDirection {
        guard previousRange.location != NSNotFound else { return .none }
        if newRange.location > previousRange.location {
            return .down
        }
        if newRange.location < previousRange.location {
            return .up
        }
        return .none
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
