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

        if let newSelection = processBlockShortcut(in: &text, at: cursorIndex) {
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
        var lineStart = text.startIndex
        var current = cursorIndex

        while current > text.startIndex {
            let prev = text.index(beforeCharacter: current)
            if text.characters[prev] == "\n" {
                lineStart = current
                break
            }
            current = prev
        }

        let lineRange = lineStart..<cursorIndex
        let lineText = String(text[lineRange].characters)

        for pattern in blockPatterns where lineText == pattern.prefix {
            text.removeSubrange(lineRange)

            let newLineStart = lineStart
            let lineEnd = nextLineEnd(in: text, from: newLineStart)

            if newLineStart < lineEnd {
                text[newLineStart..<lineEnd].blockKind = pattern.blockKind
                if let listDepth = pattern.listDepth {
                    text[newLineStart..<lineEnd].listDepth = listDepth
                }
                applyPresentationIntent(
                    to: &text,
                    range: newLineStart..<lineEnd,
                    blockKind: pattern.blockKind,
                    listDepth: pattern.listDepth
                )
            }

            return AttributedTextSelection(range: newLineStart..<newLineStart)
        }

        if let match = lineText.wholeMatch(of: /^(\d+)\.\s$/) {
            _ = match
            text.removeSubrange(lineRange)

            let newLineStart = lineStart
            let lineEnd = nextLineEnd(in: text, from: newLineStart)

            if newLineStart < lineEnd {
                text[newLineStart..<lineEnd].blockKind = .orderedList
                text[newLineStart..<lineEnd].listDepth = 1
                applyPresentationIntent(
                    to: &text,
                    range: newLineStart..<lineEnd,
                    blockKind: .orderedList,
                    listDepth: 1
                )
            }

            return AttributedTextSelection(range: newLineStart..<newLineStart)
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

        apply(&text, contentStartAttr..<contentEndAttr)

        text.removeSubrange(contentEndAttr..<cursorIndex)
        text.removeSubrange(prefixStart..<contentStartAttr)

        let newCursorIndex = text.index(prefixStart, offsetByCharacters: content.count)
        return AttributedTextSelection(range: newCursorIndex..<newCursorIndex)
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
        case .paragraph, .imageCaption, .gallery, .htmlBlock:
            text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(.paragraph, identity: 1)
        }
    }
}
