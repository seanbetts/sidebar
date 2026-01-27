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

        if lastInsertedCharacter?.isNewline == true,
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
        guard text.characters[previousIndex].isNewline else { return nil }

        var lineStart = text.startIndex
        var current = previousIndex

        while current > text.startIndex {
            let prev = text.index(beforeCharacter: current)
            if text.characters[prev].isNewline {
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
            if text.characters[current].isNewline {
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
        if lineEnd < text.endIndex, text.characters[lineEnd].isNewline {
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

    private static func listDelimiter(for blockKind: BlockKind) -> String? {
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

    private static func applyBlockStyle(
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
