// swiftlint:disable file_length
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

    func applyTableLayout(in text: inout AttributedString, lines: [LineInfo]) {
        let string = String(text.characters)
        let nsText = NSAttributedString(text)
        let cellPaddingX = em(0.75, fontSize: baseFontSize)

        var index = 0
        while index < lines.count {
            let line = lines[index]
            let lineRange = attributedRange(for: line.range, in: text)
            guard let info = tableRowInfo(in: text, range: lineRange) else {
                index += 1
                continue
            }

            let group = tableRowGroup(
                from: lines,
                startIndex: index,
                startRange: lineRange,
                startInfo: info,
                text: text
            )
            let columnWidths = tableColumnWidths(
                for: group.ranges,
                text: text,
                string: string,
                nsText: nsText,
                cellPaddingX: cellPaddingX
            )
            let tabStops = tableTabStops(
                columnWidths: columnWidths,
                alignments: group.alignments,
                cellPaddingX: cellPaddingX
            )
            applyTableTabStops(
                tabStops,
                cellPaddingX: cellPaddingX,
                to: &text,
                ranges: group.ranges
            )

            index = group.endIndex + 1
        }
    }

    struct TableRowGroup {
        let ranges: [Range<AttributedString.Index>]
        let endIndex: Int
        let alignments: [PresentationIntent.TableColumn.Alignment]
    }

    func tableRowGroup(
        from lines: [LineInfo],
        startIndex: Int,
        startRange: Range<AttributedString.Index>,
        startInfo: TableRowInfo,
        text: AttributedString
    ) -> TableRowGroup {
        var ranges: [Range<AttributedString.Index>] = [startRange]
        var alignments = startInfo.alignments ?? []
        var endIndex = startIndex
        var nextIndex = startIndex + 1

        while nextIndex < lines.count {
            let line = lines[nextIndex]
            let range = attributedRange(for: line.range, in: text)
            guard let rowInfo = tableRowInfo(in: text, range: range) else { break }
            ranges.append(range)
            if alignments.isEmpty, let rowAlignments = rowInfo.alignments, !rowAlignments.isEmpty {
                alignments = rowAlignments
            }
            endIndex = nextIndex
            nextIndex += 1
        }

        return TableRowGroup(ranges: ranges, endIndex: endIndex, alignments: alignments)
    }

    func tableColumnWidths(
        for ranges: [Range<AttributedString.Index>],
        text: AttributedString,
        string: String,
        nsText: NSAttributedString,
        cellPaddingX: CGFloat
    ) -> [CGFloat] {
        var columnWidths: [CGFloat] = []

        for range in ranges {
            let cellRanges = splitCellRanges(in: text, lineRange: range)
            for (columnIndex, cellRange) in cellRanges.enumerated() {
                let nsRange = nsRange(for: cellRange, in: text, string: string)
                let measured = nsText.attributedSubstring(from: nsRange)
                    .boundingRect(
                        with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil
                    ).width
                let width = measured + cellPaddingX * 2
                if columnIndex >= columnWidths.count {
                    columnWidths.append(width)
                } else {
                    columnWidths[columnIndex] = max(columnWidths[columnIndex], width)
                }
            }
        }

        return columnWidths
    }

    func tableTabStops(
        columnWidths: [CGFloat],
        alignments: [PresentationIntent.TableColumn.Alignment],
        cellPaddingX: CGFloat
    ) -> [NSTextTab] {
        var tabStops: [NSTextTab] = []
        var position = cellPaddingX

        for (index, width) in columnWidths.enumerated() {
            position += width
            let alignment = alignments.indices.contains(index) ? alignments[index] : .left
            let textAlignment: NSTextAlignment
            switch alignment {
            case .center:
                textAlignment = .center
            case .right:
                textAlignment = .right
            default:
                textAlignment = .left
            }
            tabStops.append(NSTextTab(textAlignment: textAlignment, location: position, options: [:]))
        }

        return tabStops
    }

    func applyTableTabStops(
        _ tabStops: [NSTextTab],
        cellPaddingX: CGFloat,
        to text: inout AttributedString,
        ranges: [Range<AttributedString.Index>]
    ) {
        for range in ranges {
            let currentStyle = (text[range].paragraphStyle?.mutableCopy() as? NSMutableParagraphStyle)
                ?? NSMutableParagraphStyle()
            currentStyle.tabStops = tabStops
            currentStyle.defaultTabInterval = tabStops.last?.location ?? currentStyle.defaultTabInterval
            let baseHead = currentStyle.headIndent
            currentStyle.headIndent = baseHead + cellPaddingX
            currentStyle.firstLineHeadIndent = baseHead + cellPaddingX
            if currentStyle.tailIndent == 0 {
                currentStyle.tailIndent = -cellPaddingX
            } else {
                currentStyle.tailIndent -= cellPaddingX
            }
            text[range].paragraphStyle = currentStyle
        }
    }

    func attributedRange(for range: Range<Int>, in text: AttributedString) -> Range<AttributedString.Index> {
        let start = text.index(text.startIndex, offsetByCharacters: range.lowerBound)
        let end = text.index(text.startIndex, offsetByCharacters: range.upperBound)
        return start..<end
    }

    func splitCellRanges(
        in text: AttributedString,
        lineRange: Range<AttributedString.Index>
    ) -> [Range<AttributedString.Index>] {
        var ranges: [Range<AttributedString.Index>] = []
        var start = lineRange.lowerBound
        var current = lineRange.lowerBound

        while current < lineRange.upperBound {
            if text.characters[current] == "\t" {
                ranges.append(start..<current)
                let next = text.index(afterCharacter: current)
                start = next
                current = next
            } else {
                current = text.index(afterCharacter: current)
            }
        }

        ranges.append(start..<lineRange.upperBound)
        return ranges
    }

    func nsRange(
        for range: Range<AttributedString.Index>,
        in text: AttributedString,
        string: String
    ) -> NSRange {
        let lowerOffset = text.characters.distance(from: text.startIndex, to: range.lowerBound)
        let upperOffset = text.characters.distance(from: text.startIndex, to: range.upperBound)
        let lowerIndex = string.index(string.startIndex, offsetBy: lowerOffset)
        let upperIndex = string.index(string.startIndex, offsetBy: upperOffset)
        let location = lowerIndex.utf16Offset(in: string)
        let length = upperIndex.utf16Offset(in: string) - location
        return NSRange(location: location, length: max(0, length))
    }

    func tableRowInfo(
        in text: AttributedString,
        range: Range<AttributedString.Index>
    ) -> TableRowInfo? {
        var isHeader = false
        var rowIndex: Int?
        var alignments: [PresentationIntent.TableColumn.Alignment]?
        var hasCell = false

        for run in text[range].runs {
            guard let intent = run[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] else { continue }
            for component in intent.components {
                switch component.kind {
                case .tableHeaderRow:
                    isHeader = true
                    rowIndex = 0
                case .tableRow(let index):
                    rowIndex = index
                case .tableCell:
                    hasCell = true
                case .table(let columns):
                    alignments = columns.map { $0.alignment }
                default:
                    break
                }
            }
        }

        guard hasCell else { return nil }
        return TableRowInfo(isHeader: isHeader, rowIndex: rowIndex, alignments: alignments)
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

    func lineIndexForSelection(in text: AttributedString) -> Int? {
        let ranges = lineRanges(in: text)
        let selectionIndex: AttributedString.Index?

        switch selection.indices(in: text) {
        case .insertionPoint(let index):
            selectionIndex = index
        case .ranges(let set):
            selectionIndex = set.ranges.first?.lowerBound
        }

        guard let selectionIndex else { return nil }

        for (lineIndex, range) in ranges.enumerated() {
            if range.contains(selectionIndex) || selectionIndex == range.upperBound {
                return lineIndex
            }
        }
        return nil
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
        lineText: String
    ) -> [Range<AttributedString.Index>] {
        let attributedRanges = inlineMarkerRanges(in: text, lineRange: lineRange)
        if !attributedRanges.isEmpty {
            return attributedRanges
        }

        let patterns = [
            #"\*\*"#,
            #"__"#,
            #"~~"#,
            #"(?<!\*)\*(?!\*)"#,
            #"(?<!_)_(?!_)"#,
            #"(?<!`)`(?!`)"#
        ]
        var ranges: [Range<AttributedString.Index>] = []

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsRange = NSRange(location: 0, length: lineText.utf16.count)
            for match in regex.matches(in: lineText, range: nsRange) {
                guard let matchRange = Range(match.range, in: lineText) else { continue }
                let startOffset = lineText.distance(from: lineText.startIndex, to: matchRange.lowerBound)
                let endOffset = lineText.distance(from: lineText.startIndex, to: matchRange.upperBound)
                let start = text.index(lineRange.lowerBound, offsetByCharacters: startOffset)
                let end = text.index(lineRange.lowerBound, offsetByCharacters: endOffset)
                let range = start..<end
                text[range].inlineMarker = true
                ranges.append(range)
            }
        }

        return ranges
    }

}
