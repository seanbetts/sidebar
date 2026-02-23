import CoreGraphics
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum MarkdownHeadingMetrics {
    static let lineSpacingEm: CGFloat = 0.3
    static let spacingBeforeRem: CGFloat = 0.5
    static let spacingAfterRem: CGFloat = 0

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
        true
    }

    static func paragraphStyle(level: Int, baseFontSize: CGFloat) -> NSParagraphStyle {
        let fontSize = fontSize(for: level, baseFontSize: baseFontSize)
        let spacingBefore = (level == 1 ? 0 : spacingBeforeRem) * baseFontSize
        let spacingAfter = spacingAfterRem * baseFontSize
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacingEm * fontSize
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacingAfter
        return style
    }
}
