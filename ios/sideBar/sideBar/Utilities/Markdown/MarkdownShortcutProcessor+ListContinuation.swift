import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
extension MarkdownShortcutProcessor {
    static func continueListOnNewlineIfNeeded(
        in text: inout AttributedString,
        previousLineRange: Range<AttributedString.Index>,
        previousLineText: String,
        insertionIndex: AttributedString.Index,
        baseFontSize: CGFloat
    ) -> AttributedTextSelection? {
        let previousBlockKind = text.blockKind(in: previousLineRange) ?? inferredListBlockKind(from: previousLineText)
        guard let previousBlockKind,
              let continuationBlockKind = listContinuationBlockKind(for: previousBlockKind)
        else {
            return nil
        }

        if isEmptyListItemLine(previousLineText, blockKind: previousBlockKind) {
            return exitListFromEmptyItem(
                in: &text,
                previousLineRange: previousLineRange,
                insertionIndex: insertionIndex,
                baseFontSize: baseFontSize
            )
        }

        let previousDepth = max(1, text[previousLineRange].listDepth ?? 1)
        let currentLineEnd = nextLineEnd(in: text, from: insertionIndex)
        let currentLineRange = insertionIndex..<currentLineEnd

        if insertionIndex == currentLineEnd {
            return insertContinuationMarker(
                in: &text,
                insertionIndex: insertionIndex,
                blockKind: continuationBlockKind,
                depth: previousDepth,
                previousLineText: previousLineText,
                baseFontSize: baseFontSize
            )
        }

        text[currentLineRange].blockKind = continuationBlockKind
        text[currentLineRange].listDepth = previousDepth
        applyPresentationIntent(
            to: &text,
            range: currentLineRange,
            blockKind: continuationBlockKind,
            listDepth: previousDepth
        )
        applyBlockStyle(
            to: &text,
            range: currentLineRange,
            blockKind: continuationBlockKind,
            listDepth: previousDepth,
            baseFontSize: baseFontSize
        )

        return AttributedTextSelection(range: insertionIndex..<insertionIndex)
    }

    static func listContinuationBlockKind(for blockKind: BlockKind) -> BlockKind? {
        switch blockKind {
        case .bulletList:
            return .bulletList
        case .orderedList:
            return .orderedList
        case .taskChecked, .taskUnchecked:
            return .taskUnchecked
        default:
            return nil
        }
    }

    static func inferredListBlockKind(from lineText: String) -> BlockKind? {
        MarkdownLineInference.inferListBlockKind(from: lineText)
    }

    private static func insertContinuationMarker(
        in text: inout AttributedString,
        insertionIndex: AttributedString.Index,
        blockKind: BlockKind,
        depth: Int,
        previousLineText: String,
        baseFontSize: CGFloat
    ) -> AttributedTextSelection {
        let markerText: String
        switch blockKind {
        case .orderedList:
            markerText = "\(nextOrderedOrdinal(from: previousLineText)).  "
        case .taskUnchecked:
            markerText = "☐ "
        default:
            markerText = "•  "
        }

        var marker = AttributedString(markerText)
        let markerRange = marker.startIndex..<marker.endIndex
        marker[markerRange].blockKind = blockKind
        marker[markerRange].listDepth = depth
        marker[markerRange].listMarker = true
        applyPresentationIntent(
            to: &marker,
            range: markerRange,
            blockKind: blockKind,
            listDepth: depth
        )
        applyBlockStyle(
            to: &marker,
            range: markerRange,
            blockKind: blockKind,
            listDepth: depth,
            baseFontSize: baseFontSize
        )
        text.insert(marker, at: insertionIndex)
        let nextCursor = text.index(insertionIndex, offsetByCharacters: markerText.count)
        return AttributedTextSelection(range: nextCursor..<nextCursor)
    }

    private static func exitListFromEmptyItem(
        in text: inout AttributedString,
        previousLineRange: Range<AttributedString.Index>,
        insertionIndex: AttributedString.Index,
        baseFontSize: CGFloat
    ) -> AttributedTextSelection {
        let insertionOffset = text.characters.distance(from: text.startIndex, to: insertionIndex)
        let removedLength = text.characters.distance(from: previousLineRange.lowerBound, to: previousLineRange.upperBound)
        if removedLength > 0 {
            text.removeSubrange(previousLineRange)
        }

        let cursorOffset = max(0, insertionOffset - removedLength)
        let cursorIndex = text.index(text.startIndex, offsetByCharacters: cursorOffset)
        let currentLineEnd = nextLineEnd(in: text, from: cursorIndex)
        if cursorIndex < currentLineEnd {
            text[cursorIndex..<currentLineEnd].blockKind = .paragraph
            text[cursorIndex..<currentLineEnd].listDepth = nil
            applyPresentationIntent(
                to: &text,
                range: cursorIndex..<currentLineEnd,
                blockKind: .paragraph,
                listDepth: nil
            )
            applyBlockStyle(
                to: &text,
                range: cursorIndex..<currentLineEnd,
                blockKind: .paragraph,
                listDepth: nil,
                baseFontSize: baseFontSize
            )
        }

        return AttributedTextSelection(range: cursorIndex..<cursorIndex)
    }

    private static func isEmptyListItemLine(_ lineText: String, blockKind: BlockKind) -> Bool {
        let trimmed = lineText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }

        switch blockKind {
        case .bulletList:
            return trimmed == "•"
                || trimmed.range(of: #"^[-+*]\s*$"#, options: .regularExpression) != nil
        case .orderedList:
            return trimmed.range(of: #"^\d+\.\s*$"#, options: .regularExpression) != nil
        case .taskChecked, .taskUnchecked:
            return trimmed == "☑"
                || trimmed == "☐"
                || trimmed.range(of: #"^[-+*]\s+\[[ xX]\]\s*$"#, options: .regularExpression) != nil
        default:
            return false
        }
    }

    private static func nextOrderedOrdinal(from lineText: String) -> Int {
        let trimmed = lineText.trimmingCharacters(in: .whitespaces)
        let blockquoteMarker = NSRegularExpression.escapedPattern(
            for: String(MarkdownLineInference.renderedBlockquoteMarker)
        )
        guard let matchRange = trimmed.range(
            of: "^(?:[\(blockquoteMarker)▎>\\s]*)?(\\d+)\\.\\s*",
            options: .regularExpression
        ) else {
            return 1
        }

        let prefix = String(trimmed[matchRange])
        let number = prefix
            .replacingOccurrences(of: #"[^0-9]"#, with: "", options: .regularExpression)
        if let current = Int(number), current > 0 {
            return current + 1
        }
        return 1
    }
}
