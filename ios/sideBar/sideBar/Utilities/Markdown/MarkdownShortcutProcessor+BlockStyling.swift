import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
extension MarkdownShortcutProcessor {
    static func applyPresentationIntent(
        to text: inout AttributedString,
        range: Range<AttributedString.Index>,
        blockKind: BlockKind,
        listDepth: Int?
    ) {
        if let headingLevel = headingLevel(for: blockKind) {
            applyHeadingIntent(to: &text, range: range, level: headingLevel)
            return
        }

        if applyListIntent(to: &text, range: range, blockKind: blockKind, listDepth: listDepth) {
            return
        }

        switch blockKind {
        case .blockquote:
            let quoteIntent = PresentationIntent(.blockQuote, identity: 1)
            text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
                .paragraph,
                identity: 1,
                parent: quoteIntent
            )
        case .codeBlock:
            text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
                .codeBlock(languageHint: nil),
                identity: 1
            )
        case .horizontalRule:
            text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
                .thematicBreak,
                identity: 1
            )
        case .paragraph, .blankLine, .imageCaption, .gallery, .htmlBlock:
            text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
                .paragraph,
                identity: 1
            )
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6,
                .bulletList, .orderedList, .taskUnchecked, .taskChecked:
            break
        @unknown default:
            break
        }
    }

    static func headingLevel(for blockKind: BlockKind) -> Int? {
        switch blockKind {
        case .heading1: return 1
        case .heading2: return 2
        case .heading3: return 3
        case .heading4: return 4
        case .heading5: return 5
        case .heading6: return 6
        default: return nil
        }
    }

    static func applyHeadingIntent(
        to text: inout AttributedString,
        range: Range<AttributedString.Index>,
        level: Int
    ) {
        text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
            .header(level: level),
            identity: level
        )
    }

    static func applyListIntent(
        to text: inout AttributedString,
        range: Range<AttributedString.Index>,
        blockKind: BlockKind,
        listDepth: Int?
    ) -> Bool {
        guard let listKind = listKind(for: blockKind) else {
            return false
        }

        let listId = listDepth ?? 1
        let listIntent = PresentationIntent(listKind, identity: listId)
        let listItemIntent = PresentationIntent(
            .listItem(ordinal: 1),
            identity: listId * 1000 + 1,
            parent: listIntent
        )

        text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
            .paragraph,
            identity: 1,
            parent: listItemIntent
        )
        text[range][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = listDelimiter(for: blockKind)
        return true
    }

    static func listDelimiter(for blockKind: BlockKind) -> Character? {
        switch blockKind {
        case .bulletList:
            return "•"
        case .taskChecked:
            return "☑"
        case .taskUnchecked:
            return "☐"
        default:
            return nil
        }
    }

    static func applyBlockStyle(
        to text: inout AttributedString,
        range: Range<AttributedString.Index>,
        blockKind: BlockKind,
        listDepth: Int?,
        baseFontSize: CGFloat
    ) {
        text[range].font = blockFont(for: blockKind, baseFontSize: baseFontSize)
        if let backgroundColor = blockBackgroundColor(for: blockKind) {
            text[range].backgroundColor = backgroundColor
        }
        text[range].foregroundColor = blockForegroundColor(for: blockKind)
        text[range].paragraphStyle = blockParagraphStyle(
            for: blockKind,
            listDepth: listDepth,
            baseFontSize: baseFontSize
        )
        if blockKind == .taskChecked {
            text[range].strikethroughStyle = .single
        }
    }

    static func blockFont(for blockKind: BlockKind, baseFontSize: CGFloat) -> Font {
        if let level = headingLevel(for: blockKind) {
            return headingFont(for: level, baseFontSize: baseFontSize)
        }
        if blockKind == .codeBlock {
            return inlineCodeFont(baseFontSize: baseFontSize)
        }
        return Font.system(size: baseFontSize)
    }

    static func headingFont(for level: Int, baseFontSize: CGFloat) -> Font {
        let weight: Font.Weight = level == 1 ? .bold : .semibold
        return .system(size: MarkdownHeadingMetrics.fontSize(for: level, baseFontSize: baseFontSize), weight: weight)
    }

    static func inlineCodeFont(baseFontSize: CGFloat) -> Font {
        Font.system(
            size: MarkdownTypography.inlineCodeFontSize(baseFontSize: baseFontSize),
            weight: .regular,
            design: .monospaced
        )
    }

    static func blockForegroundColor(for blockKind: BlockKind) -> Color {
        switch blockKind {
        case .blockquote, .taskChecked:
            return DesignTokens.Colors.textSecondary
        default:
            return DesignTokens.Colors.textPrimary
        }
    }

    static func blockBackgroundColor(for blockKind: BlockKind) -> Color? {
        blockKind == .codeBlock ? DesignTokens.Colors.muted : nil
    }

    static func blockParagraphStyle(
        for blockKind: BlockKind,
        listDepth: Int?,
        baseFontSize: CGFloat
    ) -> NSParagraphStyle? {
        if let level = headingLevel(for: blockKind) {
            return MarkdownHeadingMetrics.paragraphStyle(level: level, baseFontSize: baseFontSize)
        }

        switch blockKind {
        case .paragraph:
            return MarkdownParagraphMetrics.bodyParagraphStyle(baseFontSize: baseFontSize)
        case .blockquote:
            return MarkdownParagraphMetrics.blockquoteParagraphStyle(
                baseFontSize: baseFontSize,
                headIndent: MarkdownParagraphMetrics.blockquoteIndentEm * baseFontSize
            )
        case .bulletList, .orderedList, .taskChecked, .taskUnchecked:
            let depth = max(1, listDepth ?? 1)
            let listIndent = CGFloat(depth) * 1.5 * baseFontSize
            return MarkdownParagraphMetrics.listParagraphStyle(
                baseFontSize: baseFontSize,
                listDepth: depth,
                headIndent: listIndent
            )
        case .codeBlock:
            let style = NSMutableParagraphStyle()
            style.lineSpacing = MarkdownTypography.inlineCodeFontSize(baseFontSize: baseFontSize) * 0.5
            style.paragraphSpacingBefore = baseFontSize
            style.paragraphSpacing = baseFontSize
            style.headIndent = DesignTokens.Spacing.md
            style.firstLineHeadIndent = DesignTokens.Spacing.md
            style.tailIndent = -DesignTokens.Spacing.md
            return style
        case .horizontalRule:
            let style = NSMutableParagraphStyle()
            style.paragraphSpacingBefore = 0.75 * baseFontSize
            style.paragraphSpacing = 0.75 * baseFontSize
            return style
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6:
            return MarkdownHeadingMetrics.paragraphStyle(
                level: headingLevel(for: blockKind) ?? 1,
                baseFontSize: baseFontSize
            )
        case .blankLine, .imageCaption, .gallery, .htmlBlock:
            return nil
        @unknown default:
            return nil
        }
    }

    static func listKind(for blockKind: BlockKind) -> PresentationIntent.Kind? {
        switch blockKind {
        case .orderedList:
            return .orderedList
        case .bulletList, .taskChecked, .taskUnchecked:
            return .unorderedList
        default:
            return nil
        }
    }
}
