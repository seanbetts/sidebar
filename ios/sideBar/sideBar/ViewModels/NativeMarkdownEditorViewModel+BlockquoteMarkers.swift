@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeMarkdownEditorViewModel {
    func normalizeBlockquoteMarkers(
        in text: inout AttributedString,
        lines: [LineInfo],
        selection: SelectionSnapshot
    ) -> SelectionSnapshot {
        var snapshot = selection

        for line in lines.reversed() {
            let lineStartOffset = line.range.lowerBound
            guard let lineRange = lineRangeStarting(at: lineStartOffset, in: text) else { continue }
            let blockKind = text.blockKind(in: lineRange) ?? inferredBlockKind(from: String(text[lineRange].characters))
            let markerRanges = blockquoteMarkerRanges(in: text, lineRange: lineRange)

            if blockKind != .blockquote {
                for range in markerRanges.reversed() {
                    let startOffset = text.characters.distance(from: text.startIndex, to: range.lowerBound)
                    let length = text.characters.distance(from: range.lowerBound, to: range.upperBound)
                    text.removeSubrange(range)
                    snapshot = adjustSnapshot(snapshot, removing: length, at: startOffset)
                }
                continue
            }

            for range in markerRanges.reversed() {
                let startOffset = text.characters.distance(from: text.startIndex, to: range.lowerBound)
                let length = text.characters.distance(from: range.lowerBound, to: range.upperBound)
                text.removeSubrange(range)
                snapshot = adjustSnapshot(snapshot, removing: length, at: startOffset)
            }

            guard let refreshedRange = lineRangeStarting(at: lineStartOffset, in: text) else { continue }
            let refreshedText = String(text[refreshedRange].characters)
            let lineStyle = text[refreshedRange].paragraphStyle
            if let prefixRange = blockquotePrefixRange(in: refreshedText) {
                let prefixStart = refreshedText.distance(from: refreshedText.startIndex, to: prefixRange.lowerBound)
                let prefixLength = refreshedText.distance(from: prefixRange.lowerBound, to: prefixRange.upperBound)
                let removeOffset = lineStartOffset + prefixStart
                guard let removeStart = safeIndex(in: text, offset: removeOffset),
                      let removeEnd = safeIndex(in: text, offset: removeOffset + prefixLength),
                      removeStart < removeEnd else { continue }
                text.removeSubrange(removeStart..<removeEnd)
                snapshot = adjustSnapshot(snapshot, removing: prefixLength, at: removeOffset)
            }

            guard let insertIndex = safeIndex(in: text, offset: lineStartOffset) else { continue }
            let markerText = "▎ "
            var marker = AttributedString(markerText)
            let markerRange = marker.startIndex..<marker.endIndex
            marker[markerRange].blockKind = .blockquote
            marker[markerRange].listMarker = true
            marker[markerRange].listDepth = nil
            let markerFont = baseFont(for: .blockquote).weight(.semibold)
            let markerPlatformFont = platformSystemFont(size: baseFontSize, weight: .semibold)
            setFont(markerFont, platformFont: markerPlatformFont, in: &marker, range: markerRange)
            setForegroundColor(DesignTokens.Colors.border, in: &marker, range: markerRange)
            if let lineStyle {
                marker[markerRange].paragraphStyle = lineStyle
            }
            text.insert(marker, at: insertIndex)
            snapshot = adjustSnapshot(snapshot, inserting: markerText.count, at: lineStartOffset)
        }

        return snapshot
    }

    func lineRangeStarting(
        at offset: Int,
        in text: AttributedString
    ) -> Range<AttributedString.Index>? {
        guard let lineStart = safeIndex(in: text, offset: offset) else { return nil }
        var lineEnd = lineStart
        while lineEnd < text.endIndex {
            if text.characters[lineEnd].isNewline {
                break
            }
            lineEnd = text.index(afterCharacter: lineEnd)
        }
        return lineStart..<lineEnd
    }

    func blockquoteMarkerRanges(
        in text: AttributedString,
        lineRange: Range<AttributedString.Index>
    ) -> [Range<AttributedString.Index>] {
        var ranges: [Range<AttributedString.Index>] = []
        for run in text[lineRange].runs {
            guard run.listMarker == true, run.blockKind == .blockquote else { continue }
            ranges.append(run.range)
        }
        return ranges
    }
}
