@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeMarkdownEditorViewModel {
    func toggleInlineIntent(_ intent: InlinePresentationIntent) {
        let ranges = selectionRanges()
        for range in ranges.ranges where !range.isEmpty {
            let current = attributedContent[range].inlinePresentationIntent ?? []
            let enabled = !current.contains(intent)
            applyInlineIntent(intent, enabled: enabled, range: range)
        }
    }

    func toggleStrikethrough() {
        let ranges = selectionRanges()
        for range in ranges.ranges where !range.isEmpty {
            if attributedContent[range].strikethroughStyle == nil {
                setStrikethrough(true, in: &attributedContent, range: range)
            } else {
                setStrikethrough(false, in: &attributedContent, range: range)
                let blockKind = attributedContent.blockKind(in: range)
                setForegroundColor(baseForegroundColor(for: blockKind), range: range)
            }
        }
    }

    func setBlockKind(_ blockKind: BlockKind, listDepth: Int? = nil) {
        let ranges = selectionRanges()
        for range in ranges.ranges {
            let paragraphRange = findParagraphRange(containing: range)
            attributedContent[paragraphRange].blockKind = blockKind
            if let listDepth {
                attributedContent[paragraphRange].listDepth = listDepth
            } else {
                attributedContent[paragraphRange].listDepth = nil
            }
            applyBlockStyle(blockKind: blockKind, range: paragraphRange)
            applyPresentationIntent(blockKind: blockKind, listDepth: listDepth, range: paragraphRange)
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
        var hr = AttributedString("---")
        let range = hr.startIndex..<hr.endIndex
        hr[range].blockKind = .horizontalRule
        setForegroundColor(DesignTokens.Colors.border, in: &hr, range: range)

        let insertIndex = selectionRanges().ranges.first?.lowerBound ?? attributedContent.endIndex
        attributedContent.insert(hr, at: insertIndex)
    }

}
