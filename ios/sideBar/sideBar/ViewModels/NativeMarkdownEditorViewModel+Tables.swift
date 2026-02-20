@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeMarkdownEditorViewModel {
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
}
