import CoreGraphics
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum MarkdownHeadingMetrics {
    static let lineSpacingEm: CGFloat = 0.3
    static let spacingBeforeRem: CGFloat = 1
    static let spacingAfterRem: CGFloat = 0

    static func fontSize(for level: Int) -> CGFloat {
        switch level {
        case 1: return 32
        case 2: return 24
        case 3: return 20
        case 4: return 18
        case 5: return 17
        default: return 16
        }
    }

    static func isBold(level: Int) -> Bool {
        true
    }

    static func paragraphStyle(level: Int, baseFontSize: CGFloat) -> NSParagraphStyle {
        let fontSize = fontSize(for: level)
        let spacingBefore = (level == 1 ? 0 : spacingBeforeRem) * baseFontSize
        let spacingAfter = spacingAfterRem * baseFontSize
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacingEm * fontSize
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacingAfter
        return style
    }
}
