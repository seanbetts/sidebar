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

        let previousDepth = max(1, text[previousLineRange].listDepth ?? 1)
        let currentLineEnd = nextLineEnd(in: text, from: insertionIndex)
        let currentLineRange = insertionIndex..<currentLineEnd

        if continuationBlockKind == .taskUnchecked, insertionIndex == currentLineEnd {
            let markerText = "☐ "
            var marker = AttributedString(markerText)
            let markerRange = marker.startIndex..<marker.endIndex
            marker[markerRange].blockKind = .taskUnchecked
            marker[markerRange].listDepth = previousDepth
            marker[markerRange].listMarker = true
            applyPresentationIntent(
                to: &marker,
                range: markerRange,
                blockKind: .taskUnchecked,
                listDepth: previousDepth
            )
            applyBlockStyle(
                to: &marker,
                range: markerRange,
                blockKind: .taskUnchecked,
                listDepth: previousDepth,
                baseFontSize: baseFontSize
            )
            text.insert(marker, at: insertionIndex)
            let nextCursor = text.index(insertionIndex, offsetByCharacters: markerText.count)
            return AttributedTextSelection(range: nextCursor..<nextCursor)
        }

        if insertionIndex < currentLineEnd {
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
        }

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
        let trimmed = lineText.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("☑ ") {
            return .taskChecked
        }
        if trimmed.hasPrefix("☐ ") {
            return .taskUnchecked
        }
        if trimmed.hasPrefix("• ") {
            return .bulletList
        }
        if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
            return .taskChecked
        }
        if trimmed.hasPrefix("- [ ] ") {
            return .taskUnchecked
        }
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return .bulletList
        }
        if trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
            return .orderedList
        }
        return nil
    }
}
