@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    func toggleInlineIntent(_ intent: InlinePresentationIntent) {
        let nonEmptyRanges = selectionRanges().ranges.filter { !$0.isEmpty }
        guard !nonEmptyRanges.isEmpty else {
            let enabled = !typingAttributesHaveInlineIntentOrTrait(
                selection.typingAttributes(in: attributedContent),
                intent: intent
            )
            applyInlineIntent(intent, enabled: enabled)
            return
        }

        let shouldEnable = nonEmptyRanges.contains { range in
            !rangeHasInlineIntentOrTrait(range, intent: intent)
        }

        for range in nonEmptyRanges {
            applyInlineIntent(intent, enabled: shouldEnable, range: range)
        }
    }

    func stripUnsupportedInlineStyles(in text: inout AttributedString) {
        for run in text.runs {
            let range = run.range
            var intents = text[range].inlinePresentationIntent ?? []
            intents.remove(.code)
            text[range].inlinePresentationIntent = intents.isEmpty ? nil : intents
            text[range].strikethroughStyle = nil
        }
    }

    func setBlockKind(_ blockKind: BlockKind, listDepth: Int? = nil) {
        let ranges = selectionRanges().ranges
        var appliedToParagraph = false

        for range in ranges {
            let paragraphRange = findParagraphRange(containing: range)
            guard !paragraphRange.isEmpty else { continue }
            appliedToParagraph = true
            attributedContent[paragraphRange].blockKind = blockKind
            if let listDepth {
                attributedContent[paragraphRange].listDepth = listDepth
            } else {
                attributedContent[paragraphRange].listDepth = nil
            }
            applyBlockStyle(blockKind: blockKind, range: paragraphRange)
            applyPresentationIntent(blockKind: blockKind, listDepth: listDepth, range: paragraphRange)
        }

        guard !appliedToParagraph else { return }
        transformSelectionAttributes { attrs in
            attrs.blockKind = blockKind
            attrs.listDepth = listDepth
            if blockKind != .codeBlock {
                attrs.codeLanguage = nil
            }
            setFont(baseFont(for: blockKind), platformFont: platformBaseFont(for: blockKind), in: &attrs)
            setForegroundColor(baseForegroundColor(for: blockKind), in: &attrs)
            setBackgroundColor(baseBackgroundColor(for: blockKind), in: &attrs)
            attrs.paragraphStyle = paragraphStyle(for: blockKind, listDepth: listDepth)
            attrs[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = typingPresentationIntent(
                blockKind: blockKind,
                listDepth: listDepth
            )
            attrs[AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = listDelimiter(for: blockKind)
            attrs.strikethroughStyle = blockKind == .taskChecked ? .single : nil
        }
    }

    func selectedParagraphRanges() -> [Range<AttributedString.Index>] {
        var ranges: [Range<AttributedString.Index>] = []
        var seen = Set<String>()

        for selectionRange in selectionRanges().ranges {
            if selectionRange.isEmpty {
                appendParagraphRange(
                    containing: selectionRange.lowerBound,
                    to: &ranges,
                    seen: &seen
                )
                continue
            }

            let lastSelectedIndex = attributedContent.index(
                beforeCharacter: selectionRange.upperBound
            )
            var cursor = selectionRange.lowerBound
            while true {
                appendParagraphRange(
                    containing: cursor,
                    to: &ranges,
                    seen: &seen
                )
                if cursor >= lastSelectedIndex {
                    break
                }
                let paragraphRange = findParagraphRange(containing: cursor..<cursor)
                guard paragraphRange.upperBound < attributedContent.endIndex else {
                    break
                }
                let nextLineStart = attributedContent.index(afterCharacter: paragraphRange.upperBound)
                guard nextLineStart > cursor else { break }
                cursor = nextLineStart
            }
        }

        return ranges
    }

    private func appendParagraphRange(
        containing index: AttributedString.Index,
        to ranges: inout [Range<AttributedString.Index>],
        seen: inout Set<String>
    ) {
        let paragraphRange = findParagraphRange(containing: index..<index)
        guard !paragraphRange.isEmpty else { return }

        let lower = attributedContent.characters.distance(from: attributedContent.startIndex, to: paragraphRange.lowerBound)
        let upper = attributedContent.characters.distance(from: attributedContent.startIndex, to: paragraphRange.upperBound)
        let key = "\(lower):\(upper)"
        guard seen.insert(key).inserted else { return }
        ranges.append(paragraphRange)
    }

    private func insertionIndex(in text: AttributedString) -> AttributedString.Index? {
        switch selection.indices(in: text) {
        case .insertionPoint(let index):
            return index
        case .ranges(let ranges):
            for range in ranges.ranges where range.isEmpty {
                return range.lowerBound
            }
            return nil
        }
    }

    func findParagraphRange(containing range: Range<AttributedString.Index>) -> Range<AttributedString.Index> {
        var start = range.lowerBound
        var end = range.upperBound

        while start > attributedContent.startIndex {
            let prev = attributedContent.index(beforeCharacter: start)
            if attributedContent.characters[prev].isNewline {
                break
            }
            start = prev
        }

        while end < attributedContent.endIndex {
            if attributedContent.characters[end].isNewline {
                break
            }
            end = attributedContent.index(afterCharacter: end)
        }

        return start..<end
    }

    func insertLink(_ url: URL) {
        let ranges = selectionRanges()
        guard let range = ranges.ranges.first else { return }

        if range.isEmpty {
            let placeholder = AttributedString("link")
            var insert = placeholder
            insert[insert.startIndex..<insert.endIndex].link = url
            attributedContent.insert(insert, at: range.lowerBound)
            let cursorIndex = attributedContent.index(range.lowerBound, offsetByCharacters: placeholder.characters.count)
            selection = AttributedTextSelection(range: cursorIndex..<cursorIndex)
        } else {
            attributedContent[range].link = url
            setForegroundColor(.accentColor, range: range)
            attributedContent[range].underlineStyle = .single
        }
    }

    func insertHorizontalRule() {
        let insertIndex = selectionRanges().ranges.first?.lowerBound ?? attributedContent.endIndex
        let needsLeadingNewline = insertIndex > attributedContent.startIndex && !attributedContent.characters[
            attributedContent.index(beforeCharacter: insertIndex)
        ].isNewline
        let needsTrailingNewline = insertIndex < attributedContent.endIndex && !attributedContent.characters[insertIndex].isNewline

        var insertionText = ""
        if needsLeadingNewline {
            insertionText += "\n"
        }
        let ruleStartOffset = insertionText.count
        insertionText += "---"
        let ruleEndOffset = insertionText.count
        if needsTrailingNewline {
            insertionText += "\n"
        }

        var insertion = AttributedString(insertionText)
        let ruleStart = insertion.index(insertion.startIndex, offsetByCharacters: ruleStartOffset)
        let ruleEnd = insertion.index(insertion.startIndex, offsetByCharacters: ruleEndOffset)
        let ruleRange = ruleStart..<ruleEnd
        insertion[ruleRange].blockKind = .horizontalRule
        insertion[ruleRange].listDepth = nil
        insertion[ruleRange][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
            .thematicBreak,
            identity: 1
        )
        setFont(
            baseFont(for: .horizontalRule),
            platformFont: platformBaseFont(for: .horizontalRule),
            in: &insertion,
            range: ruleRange
        )
        setForegroundColor(DesignTokens.Colors.border, in: &insertion, range: ruleRange)
        if let style = paragraphStyle(for: .horizontalRule) {
            insertion[ruleRange].paragraphStyle = style
        }

        attributedContent.insert(insertion, at: insertIndex)
        let insertedCursorOffset = ruleEndOffset + (needsTrailingNewline ? 1 : 0)
        let cursor = attributedContent.index(insertIndex, offsetByCharacters: insertedCursorOffset)
        selection = AttributedTextSelection(range: cursor..<cursor)
    }

    func typingPresentationIntent(
        blockKind: BlockKind,
        listDepth: Int?
    ) -> PresentationIntent {
        if let headingLevel = headingLevel(for: blockKind) {
            return PresentationIntent(.header(level: headingLevel), identity: headingLevel)
        }

        switch blockKind {
        case .bulletList, .orderedList, .taskChecked, .taskUnchecked:
            let listKind: PresentationIntent.Kind = blockKind == .orderedList ? .orderedList : .unorderedList
            let listId = listDepth ?? 1
            let listIntent = PresentationIntent(listKind, identity: listId)
            let listItemIntent = PresentationIntent(
                .listItem(ordinal: 1),
                identity: listId * 1000 + 1,
                parent: listIntent
            )
            return PresentationIntent(
                .paragraph,
                identity: 1,
                parent: listItemIntent
            )
        case .blockquote:
            let quoteIntent = PresentationIntent(.blockQuote, identity: 1)
            return PresentationIntent(
                .paragraph,
                identity: 1,
                parent: quoteIntent
            )
        case .codeBlock:
            return PresentationIntent(
                .codeBlock(languageHint: nil),
                identity: 1
            )
        case .horizontalRule:
            return PresentationIntent(
                .thematicBreak,
                identity: 1
            )
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6,
             .paragraph, .blankLine, .imageCaption, .gallery, .htmlBlock:
            return PresentationIntent(
                .paragraph,
                identity: 1
            )
        @unknown default:
            return PresentationIntent(
                .paragraph,
                identity: 1
            )
        }
    }

}
