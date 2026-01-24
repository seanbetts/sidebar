import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
public struct MarkdownShortcutProcessor {
    private static let inlinePatterns: [(prefix: String, suffix: String, intent: InlinePresentationIntent)] = [
        ("**", "**", .stronglyEmphasized),
        ("__", "__", .stronglyEmphasized),
        ("*", "*", .emphasized),
        ("_", "_", .emphasized),
        ("`", "`", .code)
    ]

    private static let strikethroughPattern = ("~~", "~~")

    private static let blockPatterns: [(prefix: String, blockKind: BlockKind, listDepth: Int?)] = [
        ("# ", .heading1, nil),
        ("## ", .heading2, nil),
        ("### ", .heading3, nil),
        ("#### ", .heading4, nil),
        ("##### ", .heading5, nil),
        ("###### ", .heading6, nil),
        ("- ", .bulletList, 1),
        ("* ", .bulletList, 1),
        ("+ ", .bulletList, 1),
        ("> ", .blockquote, nil),
        ("- [ ] ", .taskUnchecked, 1),
        ("- [x] ", .taskChecked, 1),
        ("- [X] ", .taskChecked, 1)
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

        for (prefix, blockKind, listDepth) in blockPatterns {
            if lineText == prefix {
                text.removeSubrange(lineRange)

                let newLineStart = lineStart
                let lineEnd = nextLineEnd(in: text, from: newLineStart)

                if newLineStart < lineEnd {
                    text[newLineStart..<lineEnd].blockKind = blockKind
                    if let listDepth {
                        text[newLineStart..<lineEnd].listDepth = listDepth
                    }
                }

                return AttributedTextSelection(range: newLineStart..<newLineStart)
            }
        }

        if let match = lineText.wholeMatch(of: /^(\d+)\.\s$/) {
            _ = match
            text.removeSubrange(lineRange)

            let newLineStart = lineStart
            let lineEnd = nextLineEnd(in: text, from: newLineStart)

            if newLineStart < lineEnd {
                text[newLineStart..<lineEnd].blockKind = .orderedList
                text[newLineStart..<lineEnd].listDepth = 1
            }

            return AttributedTextSelection(range: newLineStart..<newLineStart)
        }

        return nil
    }

    private static func processInlineShortcuts(
        in text: inout AttributedString,
        at cursorIndex: AttributedString.Index
    ) -> AttributedTextSelection? {
        for (prefix, suffix, intent) in inlinePatterns {
            if let result = consumeInlinePattern(
                in: &text,
                at: cursorIndex,
                prefix: prefix,
                suffix: suffix,
                apply: { range in
                    let current = text[range].inlinePresentationIntent ?? []
                    text[range].inlinePresentationIntent = current.union(intent)
                }
            ) {
                return result
            }
        }

        if let result = consumeInlinePattern(
            in: &text,
            at: cursorIndex,
            prefix: strikethroughPattern.0,
            suffix: strikethroughPattern.1,
            apply: { range in
                text[range].strikethroughStyle = .single
            }
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
        apply: (Range<AttributedString.Index>) -> Void
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

        apply(contentStartAttr..<contentEndAttr)

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
            guard let range = ranges.first, range.isEmpty else { return nil }
            return range.lowerBound
        }
    }
}
