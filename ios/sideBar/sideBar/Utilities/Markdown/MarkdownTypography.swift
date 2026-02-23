import CoreGraphics

enum MarkdownTypography {
    static let defaultBodyFontSize: CGFloat = 16
    static let inlineCodeScale: CGFloat = 0.875

    static func inlineCodeFontSize(baseFontSize: CGFloat) -> CGFloat {
        baseFontSize * inlineCodeScale
    }
}
