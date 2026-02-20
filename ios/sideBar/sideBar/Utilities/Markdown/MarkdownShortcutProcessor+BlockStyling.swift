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
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6:
            return
        case .bulletList, .orderedList, .taskChecked, .taskUnchecked:
            return
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
        @unknown default:
            return
        }
    }

    private static func headingLevel(for blockKind: BlockKind) -> Int? {
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

    private static func applyHeadingIntent(
        to text: inout AttributedString,
        range: Range<AttributedString.Index>,
        level: Int
    ) {
        text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
            .header(level: level),
            identity: level
        )
    }

    private static func applyListIntent(
        to text: inout AttributedString,
        range: Range<AttributedString.Index>,
        blockKind: BlockKind,
        listDepth: Int?
    ) -> Bool {
        guard blockKind == .bulletList
            || blockKind == .orderedList
            || blockKind == .taskChecked
            || blockKind == .taskUnchecked
        else { return false }
        let listKind: PresentationIntent.Kind = blockKind == .orderedList ? .orderedList : .unorderedList
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

    private static func listDelimiter(for blockKind: BlockKind) -> Character? {
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
        blockKind: BlockKind
    ) {
        text[range].font = blockFont(for: blockKind)
        if let backgroundColor = blockBackgroundColor(for: blockKind) {
            text[range].backgroundColor = backgroundColor
        }
        text[range].foregroundColor = blockForegroundColor(for: blockKind)
        if blockKind == .taskChecked {
            text[range].strikethroughStyle = .single
        }
    }

    private static func applyTypingAttributes(
        to attrs: inout AttributeContainer,
        blockKind: BlockKind,
        listDepth: Int?
    ) {
        attrs.font = blockFont(for: blockKind)
        attrs.foregroundColor = blockForegroundColor(for: blockKind)
        if let backgroundColor = blockBackgroundColor(for: blockKind) {
            attrs.backgroundColor = backgroundColor
        }
        if blockKind == .taskChecked {
            attrs.strikethroughStyle = .single
        }

        attrs[AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = listDelimiter(for: blockKind)

        if let listKind = listKind(for: blockKind) {
            let listId = listDepth ?? 1
            let listIntent = PresentationIntent(listKind, identity: listId)
            let listItemIntent = PresentationIntent(.listItem(ordinal: 1), identity: listId * 1000 + 1, parent: listIntent)
            attrs[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
                .paragraph,
                identity: 1,
                parent: listItemIntent
            )
        } else if blockKind == .blockquote {
            let quoteIntent = PresentationIntent(.blockQuote, identity: 1)
            attrs[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
                .paragraph,
                identity: 1,
                parent: quoteIntent
            )
        } else if blockKind == .codeBlock {
            attrs[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
                .codeBlock(languageHint: nil),
                identity: 1
            )
        } else {
            attrs[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(.paragraph, identity: 1)
        }
    }

    private static func blockFont(for blockKind: BlockKind) -> Font {
        if let level = headingLevel(for: blockKind) {
            return headingFont(for: level)
        }
        if blockKind == .codeBlock {
            return Font.system(size: 14, weight: .regular, design: .monospaced)
        }
        return Font.system(size: 16)
    }

    private static func headingFont(for level: Int) -> Font {
        switch level {
        case 1:
            return .system(size: 32, weight: .bold)
        case 2:
            return .system(size: 24, weight: .semibold)
        case 3:
            return .system(size: 20, weight: .semibold)
        case 4:
            return .system(size: 18, weight: .semibold)
        case 5:
            return .system(size: 17, weight: .semibold)
        default:
            return .system(size: 16, weight: .semibold)
        }
    }

    private static func blockForegroundColor(for blockKind: BlockKind) -> Color {
        switch blockKind {
        case .blockquote, .taskChecked:
            return DesignTokens.Colors.textSecondary
        default:
            return DesignTokens.Colors.textPrimary
        }
    }

    private static func blockBackgroundColor(for blockKind: BlockKind) -> Color? {
        blockKind == .codeBlock ? DesignTokens.Colors.muted : nil
    }

    private static func listKind(for blockKind: BlockKind) -> PresentationIntent.Kind? {
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
