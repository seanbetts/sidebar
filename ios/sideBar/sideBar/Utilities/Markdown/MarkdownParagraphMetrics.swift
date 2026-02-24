import CoreGraphics
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum MarkdownParagraphMetrics {
    static let bodyLineHeightMultiple: CGFloat = 1.7
    static let bodySpacingRem: CGFloat = 0.5
    static let listLineHeightMultiple: CGFloat = 1.4
    static let listSpacingRem: CGFloat = 0

    static func bodyParagraphStyle(
        baseFontSize: CGFloat,
        headIndent: CGFloat = 0,
        tailIndent: CGFloat = 0
    ) -> NSParagraphStyle {
        paragraphStyle(
            fontSize: baseFontSize,
            lineHeightMultiple: bodyLineHeightMultiple,
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
            fontSize: baseFontSize,
            lineHeightMultiple: listLineHeightMultiple,
            spacingBefore: listSpacingRem * baseFontSize,
            spacingAfter: listSpacingRem * baseFontSize,
            headIndent: headIndent,
            tailIndent: tailIndent
        )
    }

    private static func paragraphStyle(
        fontSize: CGFloat,
        lineHeightMultiple: CGFloat,
        spacingBefore: CGFloat,
        spacingAfter: CGFloat,
        headIndent: CGFloat,
        tailIndent: CGFloat
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 0
        let lineHeight = lineHeightMultiple * fontSize
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
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
