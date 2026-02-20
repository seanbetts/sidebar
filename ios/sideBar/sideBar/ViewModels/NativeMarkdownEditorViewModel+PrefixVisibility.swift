@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeMarkdownEditorViewModel {
    func updatePrefixVisibility() {
        let originalSnapshot = selectionSnapshot(in: attributedContent)
        var updated = attributedContent

        let originalLines = lineInfos(in: updated)
        let listOrdinals = orderedListOrdinals(in: updated, lines: originalLines)
        let adjustedSnapshot = normalizeListMarkers(
            in: &updated,
            lines: originalLines,
            listOrdinals: listOrdinals,
            selection: originalSnapshot
        )

        let lines = lineInfos(in: updated)
        applyCodeBlockSpacing(in: &updated, lines: lines)
        applyTableLayout(in: &updated, lines: lines)
        for (index, line) in lines.enumerated() {
            let lineStart = updated.index(updated.startIndex, offsetByCharacters: line.range.lowerBound)
            let lineEnd = updated.index(updated.startIndex, offsetByCharacters: line.range.upperBound)
            let lineRange = lineStart..<lineEnd
            let shouldShow = shouldShowPrefix(for: line.range, selection: adjustedSnapshot)
            let blockKind = resolvedBlockKind(in: &updated, lineRange: lineRange, lineText: line.text)
            let previousBlockKind: BlockKind? = {
                guard index > 0 else { return nil }
                let previous = lines[index - 1]
                let prevStart = updated.index(updated.startIndex, offsetByCharacters: previous.range.lowerBound)
                let prevEnd = updated.index(updated.startIndex, offsetByCharacters: previous.range.upperBound)
                let prevRange = prevStart..<prevEnd
                return updated.blockKind(in: prevRange) ?? inferredBlockKind(from: previous.text)
            }()
            let prefixRange = markdownPrefixRange(
                in: updated,
                lineRange: lineRange,
                lineText: line.text,
                blockKind: blockKind
            )

            if shouldRemoveSpacingBefore(blockKind: blockKind, previousBlockKind: previousBlockKind) {
                let listDepth = updated[lineRange].listDepth
                let baseStyle = updated[lineRange].paragraphStyle
                    ?? paragraphStyle(for: blockKind ?? .paragraph, listDepth: listDepth)
                if let baseStyle {
                    let mutable = baseStyle.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                    mutable.paragraphSpacingBefore = 0
                    updated[lineRange].paragraphStyle = mutable
                }
            }

            applyInlineIntentStyling(in: &updated, lineRange: lineRange, blockKind: blockKind)

            if let prefixRange {
                applyPrefixVisibility(
                    in: &updated,
                    range: prefixRange,
                    blockKind: blockKind,
                    shouldShow: shouldShow
                )
            }

            let inlineRanges = ensureInlineMarkerRanges(in: &updated, lineRange: lineRange, lineText: line.text)
            for inlineRange in inlineRanges {
                applyInlineMarkerVisibility(
                    in: &updated,
                    range: inlineRange,
                    blockKind: blockKind,
                    shouldShow: shouldShow
                )
            }
        }

        if updated != attributedContent {
            isUpdatingPrefixVisibility = true
            attributedContent = updated
            selection = selection(from: adjustedSnapshot, in: updated)
            Task { @MainActor [weak self] in
                self?.isUpdatingPrefixVisibility = false
            }
        }
    }

    func applyCodeBlockSpacing(in text: inout AttributedString, lines: [LineInfo]) {
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let lineStart = text.index(text.startIndex, offsetByCharacters: line.range.lowerBound)
            let lineEnd = text.index(text.startIndex, offsetByCharacters: line.range.upperBound)
            let lineRange = lineStart..<lineEnd
            let blockKind = text.blockKind(in: lineRange) ?? inferredBlockKind(from: line.text)

            guard blockKind == .codeBlock else {
                index += 1
                continue
            }

            var endIndex = index
            while endIndex + 1 < lines.count {
                let next = lines[endIndex + 1]
                let nextStart = text.index(text.startIndex, offsetByCharacters: next.range.lowerBound)
                let nextEnd = text.index(text.startIndex, offsetByCharacters: next.range.upperBound)
                let nextRange = nextStart..<nextEnd
                let nextKind = text.blockKind(in: nextRange) ?? inferredBlockKind(from: next.text)
                if nextKind == .codeBlock {
                    endIndex += 1
                } else {
                    break
                }
            }

            for lineIndex in index...endIndex {
                let info = lines[lineIndex]
                let start = text.index(text.startIndex, offsetByCharacters: info.range.lowerBound)
                let end = text.index(text.startIndex, offsetByCharacters: info.range.upperBound)
                let range = start..<end
                let isFirst = lineIndex == index
                let isLast = lineIndex == endIndex
                let style = paragraphStyle(
                    lineSpacing: em(0.5, fontSize: inlineCodeFontSize),
                    spacingBefore: isFirst ? rem(1) : 0,
                    spacingAfter: isLast ? rem(1) : 0,
                    headIndent: DesignTokens.Spacing.md,
                    tailIndent: DesignTokens.Spacing.md
                )
                text[range].paragraphStyle = style
            }

            index = endIndex + 1
        }
    }

    func resolvedBlockKind(
        in text: inout AttributedString,
        lineRange: Range<AttributedString.Index>,
        lineText: String
    ) -> BlockKind? {
        let inferred = inferredBlockKind(from: lineText)
        let blockKind = text.blockKind(in: lineRange) ?? inferred
        if blockKind == .horizontalRule, text.blockKind(in: lineRange) == nil {
            text[lineRange].blockKind = .horizontalRule
            if let paragraphStyle = paragraphStyle(for: .horizontalRule) {
                text[lineRange].paragraphStyle = paragraphStyle
            }
        }
        return blockKind
    }

    func applyPrefixVisibility(
        in text: inout AttributedString,
        range: Range<AttributedString.Index>,
        blockKind: BlockKind?,
        shouldShow: Bool
    ) {
        if shouldShow {
            setForegroundColor(DesignTokens.Colors.textSecondary, in: &text, range: range)
            setBackgroundColor(baseBackgroundColor(for: blockKind), in: &text, range: range)
            setFont(
                baseFont(for: blockKind),
                platformFont: platformBaseFont(for: blockKind),
                in: &text,
                range: range
            )
            return
        }

        setForegroundColor(.clear, in: &text, range: range)
        setBackgroundColor(nil, in: &text, range: range)
        if blockKind == .horizontalRule {
            setFont(
                baseFont(for: blockKind),
                platformFont: platformBaseFont(for: blockKind),
                in: &text,
                range: range
            )
        } else {
            setFont(
                .system(size: 0.1),
                platformFont: platformSystemFont(size: 0.1, weight: .regular),
                in: &text,
                range: range
            )
        }
    }

    func applyInlineMarkerVisibility(
        in text: inout AttributedString,
        range: Range<AttributedString.Index>,
        blockKind: BlockKind?,
        shouldShow: Bool
    ) {
        if shouldShow {
            setForegroundColor(DesignTokens.Colors.textSecondary, in: &text, range: range)
            setBackgroundColor(nil, in: &text, range: range)
            setFont(
                baseFont(for: blockKind),
                platformFont: platformBaseFont(for: blockKind),
                in: &text,
                range: range
            )
            return
        }

        setForegroundColor(.clear, in: &text, range: range)
        setBackgroundColor(nil, in: &text, range: range)
        if blockKind == .horizontalRule {
            setFont(
                baseFont(for: blockKind),
                platformFont: platformBaseFont(for: blockKind),
                in: &text,
                range: range
            )
        } else {
            setFont(
                .system(size: 0.1),
                platformFont: platformSystemFont(size: 0.1, weight: .regular),
                in: &text,
                range: range
            )
        }
    }

    func attributedRange(for range: Range<Int>, in text: AttributedString) -> Range<AttributedString.Index> {
        let start = text.index(text.startIndex, offsetByCharacters: range.lowerBound)
        let end = text.index(text.startIndex, offsetByCharacters: range.upperBound)
        return start..<end
    }

    func lineRanges(in text: AttributedString) -> [Range<AttributedString.Index>] {
        var lines: [Range<AttributedString.Index>] = []
        var start = text.startIndex
        var current = text.startIndex

        while current < text.endIndex {
            if text.characters[current].isNewline {
                lines.append(start..<current)
                start = text.index(afterCharacter: current)
                current = start
            } else {
                current = text.index(afterCharacter: current)
            }
        }

        if start <= text.endIndex {
            lines.append(start..<text.endIndex)
        }

        return lines
    }

    func selectionLineSpan(in text: AttributedString) -> ClosedRange<Int>? {
        let ranges = lineRanges(in: text)
        var coveredLineIndexes = IndexSet()

        func includeLines(containing index: AttributedString.Index) {
            for (lineIndex, range) in ranges.enumerated() {
                if range.contains(index) || index == range.upperBound {
                    coveredLineIndexes.insert(lineIndex)
                    return
                }
            }
        }

        switch selection.indices(in: text) {
        case .insertionPoint(let index):
            includeLines(containing: index)
        case .ranges(let selectedRanges):
            for selectedRange in selectedRanges.ranges {
                if selectedRange.isEmpty {
                    includeLines(containing: selectedRange.lowerBound)
                } else {
                    for (lineIndex, lineRange) in ranges.enumerated() where lineRange.overlaps(selectedRange) {
                        coveredLineIndexes.insert(lineIndex)
                    }
                }
            }
        }

        guard let lower = coveredLineIndexes.first,
              let upper = coveredLineIndexes.last else { return nil }
        return lower...upper
    }

    func markdownPrefixRange(
        in text: AttributedString,
        lineRange: Range<AttributedString.Index>,
        lineText: String,
        blockKind: BlockKind?
    ) -> Range<AttributedString.Index>? {
        if blockKind == .horizontalRule {
            return lineRange
        }
        if let blockKind, let range = prefixRangeForBlockKind(
            blockKind,
            in: text,
            lineRange: lineRange,
            lineText: lineText
        ) {
            guard !containsListMarker(in: text, range: range) else { return nil }
            return range
        }

        let range = NSRange(location: 0, length: lineText.utf16.count)
        let regexes = [
            Self.taskRegex,
            Self.orderedRegex,
            Self.bulletRegex,
            Self.headingRegex,
            Self.quoteRegex
        ]

        for regex in regexes {
            guard let regex, let match = regex.firstMatch(in: lineText, range: range) else { continue }
            guard let matchRange = Range(match.range, in: lineText) else { continue }
            let prefixCount = lineText.distance(from: lineText.startIndex, to: matchRange.upperBound)
            let prefixEnd = text.index(lineRange.lowerBound, offsetByCharacters: prefixCount)
            let range = lineRange.lowerBound..<prefixEnd
            guard !containsListMarker(in: text, range: range) else { return nil }
            return range
        }

        return nil
    }

    func containsListMarker(
        in text: AttributedString,
        range: Range<AttributedString.Index>
    ) -> Bool {
        for run in text[range].runs where run.listMarker == true {
            return true
        }
        return false
    }

    func prefixRangeForBlockKind(
        _ blockKind: BlockKind,
        in text: AttributedString,
        lineRange: Range<AttributedString.Index>,
        lineText: String
    ) -> Range<AttributedString.Index>? {
        let prefix: String
        switch blockKind {
        case .heading1:
            prefix = "# "
        case .heading2:
            prefix = "## "
        case .heading3:
            prefix = "### "
        case .heading4:
            prefix = "#### "
        case .heading5:
            prefix = "##### "
        case .heading6:
            prefix = "###### "
        default:
            return nil
        }

        guard let firstNonWhitespace = lineText.firstIndex(where: { !$0.isWhitespace }) else {
            return nil
        }
        guard lineText[firstNonWhitespace...].hasPrefix(prefix) else {
            return nil
        }

        let leadingOffset = lineText.distance(from: lineText.startIndex, to: firstNonWhitespace)
        let prefixEnd = text.index(lineRange.lowerBound, offsetByCharacters: leadingOffset + prefix.count)
        return lineRange.lowerBound..<prefixEnd
    }

    func inlineMarkerRanges(
        in text: AttributedString,
        lineRange: Range<AttributedString.Index>
    ) -> [Range<AttributedString.Index>] {
        var ranges: [Range<AttributedString.Index>] = []
        for run in text[lineRange].runs {
            guard run.inlineMarker == true else { continue }
            ranges.append(run.range)
        }
        return ranges
    }

    func ensureInlineMarkerRanges(
        in text: inout AttributedString,
        lineRange: Range<AttributedString.Index>,
        lineText _: String
    ) -> [Range<AttributedString.Index>] {
        inlineMarkerRanges(in: text, lineRange: lineRange)
    }

}
