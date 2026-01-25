import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
public struct MarkdownShortcutProcessor {
    private struct InlinePattern {
        let prefix: String
        let suffix: String
        let intent: InlinePresentationIntent
    }

    private struct BlockPattern {
        let prefix: String
        let blockKind: BlockKind
        let listDepth: Int?
    }

    private static let inlinePatterns: [InlinePattern] = [
        InlinePattern(prefix: "**", suffix: "**", intent: .stronglyEmphasized),
        InlinePattern(prefix: "__", suffix: "__", intent: .stronglyEmphasized),
        InlinePattern(prefix: "*", suffix: "*", intent: .emphasized),
        InlinePattern(prefix: "_", suffix: "_", intent: .emphasized),
        InlinePattern(prefix: "`", suffix: "`", intent: .code)
    ]

    private static let strikethroughPattern = InlinePattern(prefix: "~~", suffix: "~~", intent: .stronglyEmphasized)
    private static let inlineCodeFont = Font.system(size: 14, weight: .regular, design: .monospaced)

    private static let blockPatterns: [BlockPattern] = [
        BlockPattern(prefix: "# ", blockKind: .heading1, listDepth: nil),
        BlockPattern(prefix: "## ", blockKind: .heading2, listDepth: nil),
        BlockPattern(prefix: "### ", blockKind: .heading3, listDepth: nil),
        BlockPattern(prefix: "#### ", blockKind: .heading4, listDepth: nil),
        BlockPattern(prefix: "##### ", blockKind: .heading5, listDepth: nil),
        BlockPattern(prefix: "###### ", blockKind: .heading6, listDepth: nil),
        BlockPattern(prefix: "- ", blockKind: .bulletList, listDepth: 1),
        BlockPattern(prefix: "* ", blockKind: .bulletList, listDepth: 1),
        BlockPattern(prefix: "+ ", blockKind: .bulletList, listDepth: 1),
        BlockPattern(prefix: "> ", blockKind: .blockquote, listDepth: nil),
        BlockPattern(prefix: "- [ ] ", blockKind: .taskUnchecked, listDepth: 1),
        BlockPattern(prefix: "- [x] ", blockKind: .taskChecked, listDepth: 1),
        BlockPattern(prefix: "- [X] ", blockKind: .taskChecked, listDepth: 1)
    ]

    public static func processShortcuts(
        in text: inout AttributedString,
        selection: AttributedTextSelection,
        lastInsertedCharacter: Character?
    ) -> AttributedTextSelection? {
        guard let cursorIndex = cursorIndex(in: text, selection: selection) else {
            return nil
        }

        if lastInsertedCharacter == "\n",
           let newSelection = processBlockShortcut(in: &text, at: cursorIndex) {
            return newSelection
        }

        if let newSelection = processInlineShortcuts(in: &text, at: cursorIndex) {
            return newSelection
        }

        return nil
    }

    private static func processBlockShortcut(
        in text: inout AttributedString,
        at cursorIndex: AttributedString.Index
    ) -> AttributedTextSelection? {
        guard cursorIndex > text.startIndex else { return nil }
        let previousIndex = text.index(beforeCharacter: cursorIndex)
        guard text.characters[previousIndex] == "\n" else { return nil }

        var lineStart = text.startIndex
        var current = previousIndex

        while current > text.startIndex {
            let prev = text.index(beforeCharacter: current)
            if text.characters[prev] == "\n" {
                lineStart = current
                break
            }
            current = prev
        }

        let lineRange = lineStart..<previousIndex
        let lineText = String(text[lineRange].characters)

        for pattern in blockPatterns where lineText.hasPrefix(pattern.prefix) {
            let updatedLineEnd = nextLineEnd(in: text, from: lineStart)
            if lineStart < updatedLineEnd {
                text[lineStart..<updatedLineEnd].blockKind = pattern.blockKind
                if let listDepth = pattern.listDepth {
                    text[lineStart..<updatedLineEnd].listDepth = listDepth
                }
                applyPresentationIntent(
                    to: &text,
                    range: lineStart..<updatedLineEnd,
                    blockKind: pattern.blockKind,
                    listDepth: pattern.listDepth
                )
                applyBlockStyle(
                    to: &text,
                    range: lineStart..<updatedLineEnd,
                    blockKind: pattern.blockKind
                )
            }

            return selectionAfterLine(in: text, lineStart: lineStart)
        }

        if let match = lineText.wholeMatch(of: /^(\d+)\.\s/) {
            _ = match
            let updatedLineEnd = nextLineEnd(in: text, from: lineStart)
            if lineStart < updatedLineEnd {
                text[lineStart..<updatedLineEnd].blockKind = .orderedList
                text[lineStart..<updatedLineEnd].listDepth = 1
                applyPresentationIntent(
                    to: &text,
                    range: lineStart..<updatedLineEnd,
                    blockKind: .orderedList,
                    listDepth: 1
                )
                applyBlockStyle(
                    to: &text,
                    range: lineStart..<updatedLineEnd,
                    blockKind: .orderedList
                )
            }

            return selectionAfterLine(in: text, lineStart: lineStart)
        }

        return nil
    }

    private static func processInlineShortcuts(
        in text: inout AttributedString,
        at cursorIndex: AttributedString.Index
    ) -> AttributedTextSelection? {
        for pattern in inlinePatterns {
            let apply: (inout AttributedString, Range<AttributedString.Index>) -> Void = { text, range in
                var slice = text[range]
                let current = slice.inlinePresentationIntent ?? []
                slice.inlinePresentationIntent = current.union(pattern.intent)
                if pattern.intent == .code {
                    slice.font = inlineCodeFont
                    slice.foregroundColor = DesignTokens.Colors.textPrimary
                    slice.backgroundColor = DesignTokens.Colors.muted
                }
                text.replaceSubrange(range, with: slice)
            }
            if let result = consumeInlinePattern(
                in: &text,
                at: cursorIndex,
                prefix: pattern.prefix,
                suffix: pattern.suffix,
                apply: apply
            ) {
                return result
            }
        }

        let applyStrike: (inout AttributedString, Range<AttributedString.Index>) -> Void = { text, range in
            var slice = text[range]
            slice.strikethroughStyle = .single
            slice.foregroundColor = DesignTokens.Colors.textSecondary
            text.replaceSubrange(range, with: slice)
        }
        if let result = consumeInlinePattern(
            in: &text,
            at: cursorIndex,
            prefix: strikethroughPattern.prefix,
            suffix: strikethroughPattern.suffix,
            apply: applyStrike
        ) {
            return result
        }

        return nil
    }

    private static func consumeInlinePattern(
        in text: inout AttributedString,
        at cursorIndex: AttributedString.Index,
        prefix: String,
        suffix: String,
        apply: (inout AttributedString, Range<AttributedString.Index>) -> Void
    ) -> AttributedTextSelection? {
        let isSingleToken = prefix.count == 1 && suffix.count == 1 && prefix == suffix
        let singleTokenChar = isSingleToken ? prefix.first : nil
        let prefixCount = prefix.count
        let suffixCount = suffix.count
        let minChars = prefixCount + 1 + suffixCount

        var searchStart = cursorIndex
        var charCount = 0

        while searchStart > text.startIndex && charCount < 200 {
            searchStart = text.index(beforeCharacter: searchStart)
            charCount += 1
        }

        let searchText = String(text[searchStart..<cursorIndex].characters)
        guard searchText.count >= minChars, searchText.hasSuffix(suffix) else {
            return nil
        }

        let withoutSuffix = String(searchText.dropLast(suffixCount))
        guard let prefixRange = withoutSuffix.range(of: prefix, options: .backwards) else {
            return nil
        }

        let contentStart = prefixRange.upperBound
        let content = String(withoutSuffix[contentStart...])
        guard !content.isEmpty else { return nil }

        let prefixStartOffset = withoutSuffix.distance(from: withoutSuffix.startIndex, to: prefixRange.lowerBound)
        let prefixStart = text.index(searchStart, offsetByCharacters: prefixStartOffset)
        let contentStartAttr = text.index(prefixStart, offsetByCharacters: prefixCount)
        let contentEndAttr = text.index(cursorIndex, offsetByCharacters: -suffixCount)

        if let tokenChar = singleTokenChar, tokenChar == "*" || tokenChar == "_" {
            if prefixStart > text.startIndex {
                let prevPrefix = text.index(beforeCharacter: prefixStart)
                if text.characters[prevPrefix] == tokenChar {
                    return nil
                }
            }
            if contentEndAttr > text.startIndex {
                let prevSuffix = text.index(beforeCharacter: contentEndAttr)
                if text.characters[prevSuffix] == tokenChar {
                    return nil
                }
            }
        }

        apply(&text, contentStartAttr..<contentEndAttr)
        text[prefixStart..<contentStartAttr].inlineMarker = true
        text[contentEndAttr..<cursorIndex].inlineMarker = true

        return AttributedTextSelection(range: cursorIndex..<cursorIndex)
    }

    private static func nextLineEnd(in text: AttributedString, from start: AttributedString.Index) -> AttributedString.Index {
        var current = start
        while current < text.endIndex {
            if text.characters[current] == "\n" {
                break
            }
            current = text.index(afterCharacter: current)
        }
        return current
    }

    private static func selectionAfterLine(
        in text: AttributedString,
        lineStart: AttributedString.Index
    ) -> AttributedTextSelection {
        let lineEnd = nextLineEnd(in: text, from: lineStart)
        if lineEnd < text.endIndex, text.characters[lineEnd] == "\n" {
            let nextIndex = text.index(afterCharacter: lineEnd)
            return AttributedTextSelection(range: nextIndex..<nextIndex)
        }
        return AttributedTextSelection(range: lineEnd..<lineEnd)
    }

    private static func cursorIndex(in text: AttributedString, selection: AttributedTextSelection) -> AttributedString.Index? {
        switch selection.indices(in: text) {
        case .insertionPoint(let index):
            return index
        case .ranges(let ranges):
            for range in ranges.ranges {
                guard range.isEmpty else { return nil }
                return range.lowerBound
            }
            return nil
        }
    }

    private static func applyPresentationIntent(
        to text: inout AttributedString,
        range: Range<AttributedString.Index>,
        blockKind: BlockKind,
        listDepth: Int?
    ) {
        switch blockKind {
        case .heading1:
            text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(.header(level: 1), identity: 1)
        case .heading2:
            text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(.header(level: 2), identity: 2)
        case .heading3:
            text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(.header(level: 3), identity: 3)
        case .heading4:
            text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(.header(level: 4), identity: 4)
        case .heading5:
            text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(.header(level: 5), identity: 5)
        case .heading6:
            text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(.header(level: 6), identity: 6)
        case .blockquote:
            let quoteIntent = PresentationIntent(.blockQuote, identity: 1)
            text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(.paragraph, identity: 1, parent: quoteIntent)
        case .codeBlock:
            text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(.codeBlock(languageHint: nil), identity: 1)
        case .horizontalRule:
            text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(.thematicBreak, identity: 1)
        case .bulletList, .orderedList, .taskChecked, .taskUnchecked:
            let listKind: PresentationIntent.Kind = blockKind == .orderedList ? .orderedList : .unorderedList
            let listId = listDepth ?? 1
            let listIntent = PresentationIntent(listKind, identity: listId)
            let listItemIntent = PresentationIntent(.listItem(ordinal: 1), identity: listId * 1000 + 1, parent: listIntent)
            text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(.paragraph, identity: 1, parent: listItemIntent)
            if blockKind == .bulletList {
                text[range][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = "•"
            } else if blockKind == .taskChecked {
                text[range][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = "☑"
            } else if blockKind == .taskUnchecked {
                text[range][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = "☐"
            } else {
                text[range][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = nil
            }
        case .paragraph, .blankLine, .imageCaption, .gallery, .htmlBlock:
            text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(.paragraph, identity: 1)
        }
    }

    private static func applyBlockStyle(
        to text: inout AttributedString,
        range: Range<AttributedString.Index>,
        blockKind: BlockKind
    ) {
        switch blockKind {
        case .heading1:
            text[range].font = .system(size: 32, weight: .bold)
        case .heading2:
            text[range].font = .system(size: 24, weight: .semibold)
        case .heading3:
            text[range].font = .system(size: 20, weight: .semibold)
        case .heading4:
            text[range].font = .system(size: 18, weight: .semibold)
        case .heading5:
            text[range].font = .system(size: 17, weight: .semibold)
        case .heading6:
            text[range].font = .system(size: 16, weight: .semibold)
        case .codeBlock:
            text[range].font = Font.system(size: 14, weight: .regular, design: .monospaced)
            text[range].backgroundColor = DesignTokens.Colors.muted
        default:
            text[range].font = Font.system(size: 16)
        }

        switch blockKind {
        case .blockquote, .taskChecked:
            text[range].foregroundColor = DesignTokens.Colors.textSecondary
        default:
            text[range].foregroundColor = DesignTokens.Colors.textPrimary
        }

        if blockKind == .taskChecked {
            text[range].strikethroughStyle = .single
            text[range].foregroundColor = DesignTokens.Colors.textSecondary
        }
    }

    private static func applyTypingAttributes(
        to attrs: inout AttributeContainer,
        blockKind: BlockKind,
        listDepth: Int?
    ) {
        switch blockKind {
        case .heading1:
            attrs.font = .system(size: 32, weight: .bold)
        case .heading2:
            attrs.font = .system(size: 24, weight: .semibold)
        case .heading3:
            attrs.font = .system(size: 20, weight: .semibold)
        case .heading4:
            attrs.font = .system(size: 18, weight: .semibold)
        case .heading5:
            attrs.font = .system(size: 17, weight: .semibold)
        case .heading6:
            attrs.font = .system(size: 16, weight: .semibold)
        case .codeBlock:
            attrs.font = Font.system(size: 14, weight: .regular, design: .monospaced)
            attrs.backgroundColor = DesignTokens.Colors.muted
        default:
            attrs.font = Font.system(size: 16)
        }

        switch blockKind {
        case .blockquote, .taskChecked:
            attrs.foregroundColor = DesignTokens.Colors.textSecondary
        default:
            attrs.foregroundColor = DesignTokens.Colors.textPrimary
        }

        if blockKind == .taskChecked {
            attrs.strikethroughStyle = .single
        }

        switch blockKind {
        case .bulletList:
            attrs[AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = "•"
        case .taskChecked:
            attrs[AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = "☑"
        case .taskUnchecked:
            attrs[AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = "☐"
        default:
            attrs[AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = nil
        }

        let listKind: PresentationIntent.Kind? = {
            switch blockKind {
            case .orderedList:
                return .orderedList
            case .bulletList, .taskChecked, .taskUnchecked:
                return .unorderedList
            default:
                return nil
            }
        }()

        if let listKind {
            let listId = listDepth ?? 1
            let listIntent = PresentationIntent(listKind, identity: listId)
            let listItemIntent = PresentationIntent(.listItem(ordinal: 1), identity: listId * 1000 + 1, parent: listIntent)
            attrs[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(.paragraph, identity: 1, parent: listItemIntent)
        } else if blockKind == .blockquote {
            let quoteIntent = PresentationIntent(.blockQuote, identity: 1)
            attrs[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(.paragraph, identity: 1, parent: quoteIntent)
        } else if blockKind == .codeBlock {
            attrs[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(.codeBlock(languageHint: nil), identity: 1)
        } else {
            attrs[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(.paragraph, identity: 1)
        }
    }
}
