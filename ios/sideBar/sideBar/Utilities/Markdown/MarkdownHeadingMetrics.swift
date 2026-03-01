import CoreGraphics
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum MarkdownHeadingMetrics {
    static let lineHeightMultiple: CGFloat = 1.3
    static let headingSpacingBeforeRem: CGFloat = 1
    static let headingSpacingAfterRem: CGFloat = 0.3

    static func fontSize(
        for level: Int,
        baseFontSize: CGFloat = MarkdownTypography.defaultBodyFontSize
    ) -> CGFloat {
        headingScale(for: level) * baseFontSize
    }

    private static func headingScale(for level: Int) -> CGFloat {
        switch level {
        case 1: return 2
        case 2: return 1.5
        case 3: return 1.25
        case 4: return 1.125
        case 5: return 1.0625
        default: return 1
        }
    }

    static func isBold(level: Int) -> Bool {
        level == 1
    }

    static func paragraphStyle(level: Int, baseFontSize: CGFloat) -> NSParagraphStyle {
        let fontSize = fontSize(for: level, baseFontSize: baseFontSize)
        let spacingBefore = (level == 1 ? 0 : headingSpacingBeforeRem) * baseFontSize
        let spacingAfter = headingSpacingAfterRem * baseFontSize
        let style = NSMutableParagraphStyle()
        let desiredLineHeight = lineHeightMultiple * fontSize
        style.lineSpacing = max(
            0,
            desiredLineHeight - naturalLineHeight(for: level, fontSize: fontSize)
        )
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacingAfter
        return style
    }

    private static func naturalLineHeight(for level: Int, fontSize: CGFloat) -> CGFloat {
#if canImport(UIKit)
        let weight: UIFont.Weight = isBold(level: level) ? .bold : .semibold
        return UIFont.systemFont(ofSize: fontSize, weight: weight).lineHeight
#elseif canImport(AppKit)
        let weight: NSFont.Weight = isBold(level: level) ? .bold : .semibold
        let font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        return font.ascender - font.descender + font.leading
#else
        return fontSize
#endif
    }
}
