import CoreGraphics

struct ChatInputSizingResult: Equatable {
    let measuredHeight: CGFloat
    let isOverflowing: Bool
}

struct ChatInputDeferredHeightState {
    private(set) var pendingMeasuredHeight: CGFloat?

    mutating func shouldSchedule(currentMeasuredHeight: CGFloat, targetMeasuredHeight: CGFloat) -> Bool {
        guard currentMeasuredHeight != targetMeasuredHeight else {
            pendingMeasuredHeight = nil
            return false
        }
        guard pendingMeasuredHeight != targetMeasuredHeight else {
            return false
        }
        pendingMeasuredHeight = targetMeasuredHeight
        return true
    }

    mutating func didApply(measuredHeight: CGFloat) {
        guard pendingMeasuredHeight == measuredHeight else { return }
        pendingMeasuredHeight = nil
    }
}

enum ChatInputSizing {
    static func resolve(contentHeight: CGFloat, minHeight: CGFloat, maxHeight: CGFloat) -> ChatInputSizingResult {
        let normalizedContent = max(0, contentHeight)
        let normalizedMin = max(0, minHeight)
        let normalizedMax = max(normalizedMin, maxHeight)
        let measuredHeight = min(normalizedMax, max(normalizedMin, normalizedContent))
        let isOverflowing = normalizedContent > normalizedMax
        return ChatInputSizingResult(measuredHeight: measuredHeight, isOverflowing: isOverflowing)
    }

    static func stateMeasuredHeight(for measuredHeight: CGFloat, minHeight: CGFloat) -> CGFloat {
        let normalizedMin = max(0, minHeight)
        return measuredHeight <= normalizedMin ? 0 : measuredHeight
    }
}

enum ChatInputInteractivity {
    static func textViewIsEditable(isEnabled: Bool, isFirstResponder: Bool) -> Bool {
        _ = isFirstResponder
        return isEnabled
    }
}
