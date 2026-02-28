import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
public struct MarkdownShortcutProcessor {
    public struct ShortcutResult {
        public let selection: AttributedTextSelection
    }

    struct InlinePattern {
        let prefix: String
        let suffix: String
        let intent: InlinePresentationIntent
    }

    struct BlockPattern {
        let prefix: String
        let blockKind: BlockKind
        let listDepth: Int?
    }

    struct BlockLineContext {
        let range: Range<AttributedString.Index>
        let lineStart: AttributedString.Index
        let lineEnd: AttributedString.Index
        let text: String
    }

    private static let inlinePatterns: [InlinePattern] = [
        InlinePattern(prefix: "**", suffix: "**", intent: .stronglyEmphasized),
        InlinePattern(prefix: "__", suffix: "__", intent: .stronglyEmphasized),
        InlinePattern(prefix: "*", suffix: "*", intent: .emphasized),
        InlinePattern(prefix: "_", suffix: "_", intent: .emphasized),
        InlinePattern(prefix: "`", suffix: "`", intent: .code)
    ]

    private static let strikethroughPattern = InlinePattern(prefix: "~~", suffix: "~~", intent: .stronglyEmphasized)
    static let blockPatterns: [BlockPattern] = [
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
        lastInsertedCharacter: Character?,
        baseFontSize: CGFloat = 16
    ) -> ShortcutResult? {
        guard let cursorIndex = cursorIndex(in: text, selection: selection) else {
            return nil
        }

        if lastInsertedCharacter?.isNewline == true,
           let shortcutResult = processBlockShortcut(
               in: &text,
               at: cursorIndex,
               baseFontSize: baseFontSize
           ) {
            return shortcutResult
        }

        if let newSelection = processInlineShortcuts(
            in: &text,
            at: cursorIndex,
            baseFontSize: baseFontSize
        ) {
            return ShortcutResult(selection: newSelection)
        }

        return nil
    }

    static func processBlockShortcut(
        in text: inout AttributedString,
        at cursorIndex: AttributedString.Index,
        baseFontSize: CGFloat
    ) -> ShortcutResult? {
        guard let context = previousLineContext(in: text, at: cursorIndex) else {
            return nil
        }

        if let pattern = blockPatterns.first(where: { context.text.hasPrefix($0.prefix) }) {
            let selection = applyPatternShortcut(
                in: &text,
                context: context,
                pattern: pattern,
                insertionIndex: cursorIndex,
                baseFontSize: baseFontSize
            )
            return ShortcutResult(selection: selection)
        }

        if context.text.wholeMatch(of: /^(\d+)\.\s/) != nil {
            let selection = applyOrderedListShortcut(
                in: &text,
                context: context,
                baseFontSize: baseFontSize
            )
            return ShortcutResult(selection: selection)
        }

        if let continuation = continueListOnNewlineIfNeeded(
            in: &text,
            previousLineRange: context.range,
            previousLineText: context.text,
            insertionIndex: cursorIndex,
            baseFontSize: baseFontSize
        ) {
            return ShortcutResult(selection: continuation)
        }

        return nil
    }

    private static func applyPatternShortcut(
        in text: inout AttributedString,
        context: BlockLineContext,
        pattern: BlockPattern,
        insertionIndex: AttributedString.Index,
        baseFontSize: CGFloat
    ) -> AttributedTextSelection {
        let updatedLineEnd = applyBlockKind(
            in: &text,
            lineStart: context.lineStart,
            lineEnd: context.lineEnd,
            blockKind: pattern.blockKind,
            listDepth: pattern.listDepth,
            baseFontSize: baseFontSize
        )

        if listContinuationBlockKind(for: pattern.blockKind) == .taskUnchecked,
           let continuation = continueListOnNewlineIfNeeded(
                in: &text,
                previousLineRange: context.lineStart..<updatedLineEnd,
                previousLineText: context.text,
                insertionIndex: insertionIndex,
                baseFontSize: baseFontSize
           ) {
            return continuation
        }

        return selectionAfterLine(in: text, lineStart: context.lineStart)
    }

    private static func applyOrderedListShortcut(
        in text: inout AttributedString,
        context: BlockLineContext,
        baseFontSize: CGFloat
    ) -> AttributedTextSelection {
        _ = applyBlockKind(
            in: &text,
            lineStart: context.lineStart,
            lineEnd: context.lineEnd,
            blockKind: .orderedList,
            listDepth: 1,
            baseFontSize: baseFontSize
        )

        return selectionAfterLine(in: text, lineStart: context.lineStart)
    }

    static func applyBlockKind(
        in text: inout AttributedString,
        lineStart: AttributedString.Index,
        lineEnd: AttributedString.Index,
        blockKind: BlockKind,
        listDepth: Int?,
        baseFontSize: CGFloat
    ) -> AttributedString.Index {
        let updatedLineEnd = nextLineEnd(in: text, from: lineStart)
        guard lineStart < updatedLineEnd else {
            return updatedLineEnd
        }

        text[lineStart..<updatedLineEnd].blockKind = blockKind
        if let listDepth {
            text[lineStart..<updatedLineEnd].listDepth = listDepth
        }
        applyPresentationIntent(
            to: &text,
            range: lineStart..<updatedLineEnd,
            blockKind: blockKind,
            listDepth: listDepth
        )
        applyBlockStyle(
            to: &text,
            range: lineStart..<updatedLineEnd,
            blockKind: blockKind,
            listDepth: listDepth,
            baseFontSize: baseFontSize
        )
        return updatedLineEnd
    }

    private static func previousLineContext(
        in text: AttributedString,
        at cursorIndex: AttributedString.Index
    ) -> BlockLineContext? {
        guard cursorIndex > text.startIndex else {
            return nil
        }

        let previousIndex = text.index(beforeCharacter: cursorIndex)
        guard text.characters[previousIndex].isNewline else {
            return nil
        }

        let lineStart = lineStart(before: previousIndex, in: text)
        let lineEnd = previousIndex
        let lineRange = lineStart..<lineEnd
        let lineText = String(text[lineRange].characters)

        return BlockLineContext(
            range: lineRange,
            lineStart: lineStart,
            lineEnd: lineEnd,
            text: lineText
        )
    }

    private static func lineStart(
        before index: AttributedString.Index,
        in text: AttributedString
    ) -> AttributedString.Index {
        var current = index

        while current > text.startIndex {
            let previous = text.index(beforeCharacter: current)
            if text.characters[previous].isNewline {
                return current
            }
            current = previous
        }

        return text.startIndex
    }

    private static func processInlineShortcuts(
        in text: inout AttributedString,
        at cursorIndex: AttributedString.Index,
        baseFontSize: CGFloat
    ) -> AttributedTextSelection? {
        for pattern in inlinePatterns {
            let apply: (inout AttributedString, Range<AttributedString.Index>) -> Void = { text, range in
                var slice = text[range]
                let current = slice.inlinePresentationIntent ?? []
                slice.inlinePresentationIntent = current.union(pattern.intent)
                if pattern.intent == .code {
                    slice.font = inlineCodeFont(baseFontSize: baseFontSize)
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

    static func nextLineEnd(in text: AttributedString, from start: AttributedString.Index) -> AttributedString.Index {
        var current = start
        while current < text.endIndex {
            if text.characters[current].isNewline {
                break
            }
            current = text.index(afterCharacter: current)
        }
        return current
    }

    static func selectionAfterLine(
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
}
