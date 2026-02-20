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

    private struct BlockLineContext {
        let lineStart: AttributedString.Index
        let lineEnd: AttributedString.Index
        let lineText: String
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
        BlockPattern(prefix: "- [ ] ", blockKind: .taskUnchecked, listDepth: 1),
        BlockPattern(prefix: "- [x] ", blockKind: .taskChecked, listDepth: 1),
        BlockPattern(prefix: "- [X] ", blockKind: .taskChecked, listDepth: 1),
        BlockPattern(prefix: "* [ ] ", blockKind: .taskUnchecked, listDepth: 1),
        BlockPattern(prefix: "* [x] ", blockKind: .taskChecked, listDepth: 1),
        BlockPattern(prefix: "* [X] ", blockKind: .taskChecked, listDepth: 1),
        BlockPattern(prefix: "+ [ ] ", blockKind: .taskUnchecked, listDepth: 1),
        BlockPattern(prefix: "+ [x] ", blockKind: .taskChecked, listDepth: 1),
        BlockPattern(prefix: "+ [X] ", blockKind: .taskChecked, listDepth: 1),
        BlockPattern(prefix: "- ", blockKind: .bulletList, listDepth: 1),
        BlockPattern(prefix: "* ", blockKind: .bulletList, listDepth: 1),
        BlockPattern(prefix: "+ ", blockKind: .bulletList, listDepth: 1),
        BlockPattern(prefix: "> ", blockKind: .blockquote, listDepth: nil)
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
        guard let lineContext = blockLineContextForShortcut(in: text, at: cursorIndex) else {
            return nil
        }

        if let newSelection = applyBlockPatternShortcut(in: &text, lineContext: lineContext) {
            return newSelection
        }

        if let newSelection = applyOrderedListShortcut(in: &text, lineContext: lineContext) {
            return newSelection
        }

        if let newSelection = applyHorizontalRuleShortcut(in: &text, lineContext: lineContext) {
            return newSelection
        }

        return applyCodeFenceShortcut(in: &text, lineContext: lineContext)
    }

    private static func blockLineContextForShortcut(
        in text: AttributedString,
        at cursorIndex: AttributedString.Index
    ) -> BlockLineContext? {
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

        let lineText = String(text[lineStart..<previousIndex].characters)
        let lineEnd = nextLineEnd(in: text, from: lineStart)
        return BlockLineContext(lineStart: lineStart, lineEnd: lineEnd, lineText: lineText)
    }

    private static func applyBlockPatternShortcut(
        in text: inout AttributedString,
        lineContext: BlockLineContext
    ) -> AttributedTextSelection? {
        guard let pattern = blockPatterns.first(where: { lineContext.lineText.hasPrefix($0.prefix) }) else {
            return nil
        }

        applyBlockShortcut(
            in: &text,
            lineContext: lineContext,
            blockKind: pattern.blockKind,
            listDepth: pattern.listDepth
        )
        return selectionAfterLine(in: text, lineStart: lineContext.lineStart)
    }

    private static func applyOrderedListShortcut(
        in text: inout AttributedString,
        lineContext: BlockLineContext
    ) -> AttributedTextSelection? {
        guard lineContext.lineText.wholeMatch(of: /^(\d+)\.\s/) != nil else {
            return nil
        }

        applyBlockShortcut(
            in: &text,
            lineContext: lineContext,
            blockKind: .orderedList,
            listDepth: 1
        )
        return selectionAfterLine(in: text, lineStart: lineContext.lineStart)
    }

    private static func applyHorizontalRuleShortcut(
        in text: inout AttributedString,
        lineContext: BlockLineContext
    ) -> AttributedTextSelection? {
        guard isHorizontalRuleShortcut(lineContext.lineText) else {
            return nil
        }

        applyBlockShortcut(
            in: &text,
            lineContext: lineContext,
            blockKind: .horizontalRule,
            listDepth: nil
        )
        return selectionAfterLine(in: text, lineStart: lineContext.lineStart)
    }

    private static func applyCodeFenceShortcut(
        in text: inout AttributedString,
        lineContext: BlockLineContext
    ) -> AttributedTextSelection? {
        guard isCodeFenceShortcut(lineContext.lineText) else {
            return nil
        }

        applyBlockShortcut(
            in: &text,
            lineContext: lineContext,
            blockKind: .codeBlock,
            listDepth: nil,
            codeLanguage: codeFenceLanguage(from: lineContext.lineText)
        )
        return selectionAfterLine(in: text, lineStart: lineContext.lineStart)
    }

    private static func applyBlockShortcut(
        in text: inout AttributedString,
        lineContext: BlockLineContext,
        blockKind: BlockKind,
        listDepth: Int?,
        codeLanguage: String? = nil
    ) {
        guard lineContext.lineStart < lineContext.lineEnd else {
            return
        }

        let lineRange = lineContext.lineStart..<lineContext.lineEnd
        text[lineRange].blockKind = blockKind
        if let listDepth {
            text[lineRange].listDepth = listDepth
        }
        if let codeLanguage {
            text[lineRange].codeLanguage = codeLanguage
        }
        applyPresentationIntent(
            to: &text,
            range: lineRange,
            blockKind: blockKind,
            listDepth: listDepth
        )
        applyBlockStyle(
            to: &text,
            range: lineRange,
            blockKind: blockKind
        )
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

    private static func isHorizontalRuleShortcut(_ lineText: String) -> Bool {
        let trimmed = lineText.trimmingCharacters(in: .whitespaces)
        return trimmed == "---" || trimmed == "***" || trimmed == "___"
    }

    private static func isCodeFenceShortcut(_ lineText: String) -> Bool {
        let trimmed = lineText.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
    }

    private static func codeFenceLanguage(from lineText: String) -> String? {
        let trimmed = lineText.trimmingCharacters(in: .whitespaces)
        let language: Substring

        if trimmed.hasPrefix("```") {
            language = trimmed.dropFirst(3)
        } else if trimmed.hasPrefix("~~~") {
            language = trimmed.dropFirst(3)
        } else {
            return nil
        }

        let normalized = language.trimmingCharacters(in: .whitespaces)
        return normalized.isEmpty ? nil : normalized
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

}
