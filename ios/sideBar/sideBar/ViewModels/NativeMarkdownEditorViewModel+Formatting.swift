@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeMarkdownEditorViewModel {
    func toggleInlineIntent(_ intent: InlinePresentationIntent) {
        let nonEmptyRanges = selectionRanges().ranges.filter { !$0.isEmpty }
        guard !nonEmptyRanges.isEmpty else {
            let current = selection.typingAttributes(in: attributedContent).inlinePresentationIntent ?? []
            let enabled = !current.contains(intent)
            applyInlineIntent(intent, enabled: enabled)
            return
        }

        let shouldEnable = nonEmptyRanges.contains { range in
            let current = attributedContent[range].inlinePresentationIntent ?? []
            return !current.contains(intent)
        }

        for range in nonEmptyRanges {
            applyInlineIntent(intent, enabled: shouldEnable, range: range)
        }
    }

    func toggleStrikethrough() {
        let nonEmptyRanges = selectionRanges().ranges.filter { !$0.isEmpty }
        guard !nonEmptyRanges.isEmpty else {
            attributedContent.transformAttributes(in: &selection) { attrs in
                let enable = attrs.strikethroughStyle == nil
                attrs.strikethroughStyle = enable ? .single : nil
                if !enable {
                    setForegroundColor(baseForegroundColor(for: attrs.blockKind), in: &attrs)
                }
            }
            return
        }

        let shouldEnable = nonEmptyRanges.contains { range in
            attributedContent[range].strikethroughStyle == nil
        }

        for range in nonEmptyRanges {
            if shouldEnable {
                setStrikethrough(true, in: &attributedContent, range: range)
            } else {
                setStrikethrough(false, in: &attributedContent, range: range)
                let blockKind = attributedContent.blockKind(in: range)
                setForegroundColor(baseForegroundColor(for: blockKind), range: range)
            }
        }
    }

    func isInlineCodeActive() -> Bool {
        hasInlineIntent(.code)
    }

    func isHeadingActive() -> Bool {
        guard let blockKind = primarySelectedParagraphBlockKind() else { return false }
        return headingLevel(for: blockKind) != nil
    }

    func isBlockKindActive(_ blockKind: BlockKind) -> Bool {
        primarySelectedParagraphBlockKind() == blockKind
    }

    func isTaskListActive() -> Bool {
        guard let blockKind = primarySelectedParagraphBlockKind() else { return false }
        return blockKind == .taskChecked || blockKind == .taskUnchecked
    }

    func canAdjustListDepth() -> Bool {
        selectedParagraphRanges().contains { paragraphRange in
            guard let blockKind = attributedContent.blockKind(in: paragraphRange) else { return false }
            return isListBlockKind(blockKind)
        }
    }

    func promoteHeading() {
        adjustHeadingLevel(delta: -1, defaultLevel: 2)
    }

    func demoteHeading() {
        adjustHeadingLevel(delta: 1, defaultLevel: 2)
    }

    func stripUnsupportedInlineStyles(in text: inout AttributedString) {
        let rangesToClear = text.runs.compactMap { run -> Range<AttributedString.Index>? in
            guard run.underlineStyle != nil else { return nil }
            guard run.link == nil else { return nil }
            return run.range
        }
        for range in rangesToClear {
            text[range].underlineStyle = nil
        }
    }

    private func primarySelectedParagraphBlockKind() -> BlockKind? {
        if attributedContent.characters.isEmpty {
            return selection.typingAttributes(in: attributedContent).blockKind
        }
        guard let selectionRange = selectionRanges().ranges.first else {
            return selection.typingAttributes(in: attributedContent).blockKind
        }
        let paragraphRange = findParagraphRange(containing: selectionRange)
        guard !paragraphRange.isEmpty else {
            return selection.typingAttributes(in: attributedContent).blockKind
        }
        return attributedContent[paragraphRange].blockKind
            ?? attributedContent.blockKind(in: paragraphRange)
            ?? selection.typingAttributes(in: attributedContent).blockKind
    }

    private func adjustHeadingLevel(delta: Int, defaultLevel: Int) {
        let paragraphRanges = selectedParagraphRanges()
        guard !paragraphRanges.isEmpty else {
            let currentKind = selection.typingAttributes(in: attributedContent).blockKind ?? .paragraph
            let targetLevel = headingLevel(for: currentKind).map { level in
                min(6, max(1, level + delta))
            } ?? defaultLevel
            setBlockKind(headingKind(for: targetLevel))
            return
        }

        for paragraphRange in paragraphRanges {
            let currentKind = attributedContent[paragraphRange].blockKind
                ?? attributedContent.blockKind(in: paragraphRange)
                ?? .paragraph
            let targetLevel = headingLevel(for: currentKind).map { level in
                min(6, max(1, level + delta))
            } ?? defaultLevel
            let targetKind = headingKind(for: targetLevel)

            attributedContent[paragraphRange].blockKind = targetKind
            attributedContent[paragraphRange].listDepth = nil
            attributedContent[paragraphRange].codeLanguage = nil

            applyBlockStyle(blockKind: targetKind, range: paragraphRange)
            applyPresentationIntent(
                blockKind: targetKind,
                listDepth: nil,
                range: paragraphRange
            )
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
        attributedContent.transformAttributes(in: &selection) { attrs in
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

    func indentListItems() {
        guard !isReadOnly else { return }
        AttributedNoteListCommands.indent(on: self)
    }

    func outdentListItems() {
        guard !isReadOnly else { return }
        AttributedNoteListCommands.outdent(on: self)
    }

    func handleListDepthKeyboardShortcut(outdent: Bool) -> Bool {
        guard !isReadOnly else { return false }
        let hasSelectedListParagraph = selectedParagraphRanges().contains { paragraphRange in
            guard let blockKind = attributedContent.blockKind(in: paragraphRange) else { return false }
            return isListBlockKind(blockKind)
        }
        guard hasSelectedListParagraph else { return false }
        if outdent {
            outdentListItems()
        } else {
            indentListItems()
        }
        return true
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
        var hr = AttributedString("---")
        let insertIndex = selectionRanges().ranges.first?.lowerBound ?? attributedContent.endIndex
        let range = hr.startIndex..<hr.endIndex
        hr[range].blockKind = .horizontalRule
        setForegroundColor(DesignTokens.Colors.border, in: &hr, range: range)
        attributedContent.insert(hr, at: insertIndex)

        let ruleEnd = attributedContent.index(insertIndex, offsetByCharacters: 3)
        let insertedRange = insertIndex..<ruleEnd
        attributedContent[insertedRange].blockKind = .horizontalRule
        setForegroundColor(DesignTokens.Colors.border, range: insertedRange)
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
