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

    func toggleStrikethrough() {
        let nonEmptyRanges = selectionRanges().ranges.filter { !$0.isEmpty }
        guard !nonEmptyRanges.isEmpty else {
            transformSelectionAttributes { attrs in
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

    func isStrikethroughActive() -> Bool {
        let nonEmptyRanges = selectionRanges().ranges.filter { !$0.isEmpty }
        if !nonEmptyRanges.isEmpty {
            return nonEmptyRanges.allSatisfy { range in
                let runs = attributedContent[range].runs
                guard !runs.isEmpty else { return false }
                return runs.allSatisfy { $0.strikethroughStyle != nil }
            }
        }

        if selection.typingAttributes(in: attributedContent).strikethroughStyle != nil {
            return true
        }

        guard let insertionIndex = insertionIndex(in: attributedContent),
              insertionIndex > attributedContent.startIndex else {
            return false
        }
        let previousIndex = attributedContent.index(beforeCharacter: insertionIndex)
        let previousRange = previousIndex..<insertionIndex
        return attributedContent[previousRange].strikethroughStyle != nil
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
            if let blockKind = attributedContent.blockKind(in: paragraphRange),
               isListBlockKind(blockKind) {
                return true
            }

            let lineText = String(attributedContent[paragraphRange].characters)
            if let inferred = inferredBlockKind(from: lineText), isListBlockKind(inferred) {
                return true
            }
            if hasLiteralListPrefix(in: lineText) {
                return true
            }

            return false
        }
    }

    func currentTextSizeDisplay() -> String {
        let size: CGFloat
        if let blockKind = primarySelectedParagraphBlockKind(),
           let level = headingLevel(for: blockKind) {
            size = NoteTextHeadingMetrics.fontSize(for: level, baseFontSize: baseFontSize)
        } else {
            size = baseFontSize
        }
        return "\(Int(size.rounded()))pt"
    }

    func promoteHeading() {
        adjustHeadingLevel(delta: -1, defaultLevel: 2)
    }

    func demoteHeading() {
        adjustHeadingLevel(delta: 1, defaultLevel: 3)
    }

    func stripUnsupportedInlineStyles(in text: inout AttributedString) {
        _ = text
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
        let selectionBefore = selectionSnapshot(in: attributedContent)
        let paragraphRanges = selectedParagraphRanges()
        guard !paragraphRanges.isEmpty else {
            let currentKind = selection.typingAttributes(in: attributedContent).blockKind ?? .paragraph
            let targetLevel = headingLevel(for: currentKind).map { level in
                min(6, max(1, level + delta))
            } ?? defaultLevel
            setBlockKind(headingKind(for: targetLevel))
            selection = selection(from: selectionBefore, in: attributedContent)
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

        selection = selection(from: selectionBefore, in: attributedContent)
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

    private func hasLiteralListPrefix(in lineText: String) -> Bool {
        let trimmed = lineText.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("•") || trimmed.hasPrefix("☐") || trimmed.hasPrefix("☑") {
            return true
        }
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return true
        }
        if trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
            return true
        }
        return false
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
