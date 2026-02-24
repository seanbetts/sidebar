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
    static let rootListSpacingRem: CGFloat = 0.5
    static let nestedListSpacingRem: CGFloat = 0
    static let blockquoteSpacingRem: CGFloat = 1
    static let blockquoteIndentEm: CGFloat = 1

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
        listDepth: Int = 1,
        headIndent: CGFloat = 0,
        tailIndent: CGFloat = 0
    ) -> NSParagraphStyle {
        let spacingRem = listDepth > 1 ? nestedListSpacingRem : rootListSpacingRem
        return paragraphStyle(
            fontSize: baseFontSize,
            lineHeightMultiple: listLineHeightMultiple,
            spacingBefore: spacingRem * baseFontSize,
            spacingAfter: spacingRem * baseFontSize,
            headIndent: headIndent,
            tailIndent: tailIndent
        )
    }

    static func blockquoteParagraphStyle(
        baseFontSize: CGFloat,
        headIndent: CGFloat
    ) -> NSParagraphStyle {
        return paragraphStyle(
            fontSize: baseFontSize,
            lineHeightMultiple: bodyLineHeightMultiple,
            spacingBefore: blockquoteSpacingRem * baseFontSize,
            spacingAfter: blockquoteSpacingRem * baseFontSize,
            headIndent: headIndent,
            tailIndent: 0
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
