import CoreGraphics
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum MarkdownParagraphMetrics {
    static let bodyLineSpacingEm: CGFloat = 0.25
    static let bodySpacingRem: CGFloat = 0.75
    static let listLineSpacingEm: CGFloat = 0.25
    static let listSpacingRem: CGFloat = 0

    static func bodyParagraphStyle(
        baseFontSize: CGFloat,
        headIndent: CGFloat = 0,
        tailIndent: CGFloat = 0
    ) -> NSParagraphStyle {
        paragraphStyle(
            lineSpacing: bodyLineSpacingEm * baseFontSize,
            spacingBefore: bodySpacingRem * baseFontSize,
            spacingAfter: bodySpacingRem * baseFontSize,
            headIndent: headIndent,
            tailIndent: tailIndent
        )
    }

    static func listParagraphStyle(
        baseFontSize: CGFloat,
        headIndent: CGFloat = 0,
        tailIndent: CGFloat = 0
    ) -> NSParagraphStyle {
        paragraphStyle(
            lineSpacing: listLineSpacingEm * baseFontSize,
            spacingBefore: listSpacingRem * baseFontSize,
            spacingAfter: listSpacingRem * baseFontSize,
            headIndent: headIndent,
            tailIndent: tailIndent
        )
    }

    private static func paragraphStyle(
        lineSpacing: CGFloat,
        spacingBefore: CGFloat,
        spacingAfter: CGFloat,
        headIndent: CGFloat,
        tailIndent: CGFloat
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacingAfter
        style.headIndent = headIndent
        style.firstLineHeadIndent = headIndent
        if tailIndent != 0 {
            style.tailIndent = -tailIndent
        }
        return style
    }
}
