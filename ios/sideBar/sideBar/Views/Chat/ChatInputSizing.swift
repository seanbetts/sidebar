import CoreGraphics

struct ChatInputSizingResult: Equatable {
    let measuredHeight: CGFloat
    let isOverflowing: Bool
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
}
