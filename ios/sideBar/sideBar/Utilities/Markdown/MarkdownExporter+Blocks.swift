import Foundation
import SwiftUI

struct TableBlock {
    let markdown: [String]
    let nextIndex: Int
}

@available(iOS 26.0, macOS 26.0, *)
func tableBlock(
    from text: AttributedString,
    lines: [Range<AttributedString.Index>],
    startIndex: Int
) -> TableBlock? {
    guard startIndex < lines.count else { return nil }
    guard tableRowInfo(in: text, range: lines[startIndex]) != nil else { return nil }

    var rows: [TableRowInfo] = []
    var index = startIndex
    var tableAlignments: [PresentationIntent.TableColumn.Alignment] = []

    while index < lines.count {
        guard let info = tableRowInfo(in: text, range: lines[index]) else { break }
        rows.append(info)
        if tableAlignments.isEmpty, let alignments = info.columnAlignments {
            tableAlignments = alignments
        }
        index += 1
    }

    guard !rows.isEmpty else { return nil }

    let headerRowIndex = rows.firstIndex(where: { $0.isHeader }) ?? 0
    let header = rows[headerRowIndex]
    let bodyRows = rows.enumerated().filter { $0.offset != headerRowIndex }.map { $0.element }
    let columnCount = max(header.cells.count, bodyRows.map(\.cells.count).max() ?? 0)

    let alignmentRow = makeAlignmentRow(columnCount: columnCount, alignments: tableAlignments)
    let headerLine = renderTableRow(header.cells)
    let bodyLines = bodyRows.map { renderTableRow($0.cells) }

    return TableBlock(
        markdown: [headerLine, alignmentRow] + bodyLines,
        nextIndex: index
    )
}

@available(iOS 26.0, macOS 26.0, *)
struct TableRowInfo {
    let cells: [String]
    let isHeader: Bool
    let columnAlignments: [PresentationIntent.TableColumn.Alignment]?
}

@available(iOS 26.0, macOS 26.0, *)
func tableRowInfo(in text: AttributedString, range: Range<AttributedString.Index>) -> TableRowInfo? {
    var isHeader = false
    var alignments: [PresentationIntent.TableColumn.Alignment]?
    var hasTableCell = false

    for run in text[range].runs {
        guard let intent = run[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] else { continue }
        for component in intent.components {
            switch component.kind {
            case .tableHeaderRow:
                isHeader = true
            case .tableRow:
                break
            case .tableCell:
                hasTableCell = true
            case .table(let columns):
                alignments = columns.map { $0.alignment }
            default:
                break
            }
        }
    }

    guard hasTableCell else { return nil }

    let cellRanges = splitCellRanges(in: text, lineRange: range)
    let cells = cellRanges.map { range in
        serializeInline(text[range]).replacingOccurrences(of: "|", with: "\\|")
    }

    return TableRowInfo(cells: cells, isHeader: isHeader, columnAlignments: alignments)
}

@available(iOS 26.0, macOS 26.0, *)
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

@available(iOS 26.0, macOS 26.0, *)
func makeAlignmentRow(
    columnCount: Int,
    alignments: [PresentationIntent.TableColumn.Alignment]
) -> String {
    guard columnCount > 0 else { return "| --- |" }
    var parts: [String] = []
    for index in 0..<columnCount {
        let alignment = alignments.indices.contains(index) ? alignments[index] : .left
        switch alignment {
        case .center:
            parts.append(":---:")
        case .right:
            parts.append("---:")
        case .left:
            parts.append("---")
        @unknown default:
            parts.append("---")
        }
    }
    return "| " + parts.joined(separator: " | ") + " |"
}

@available(iOS 26.0, macOS 26.0, *)
func renderTableRow(_ cells: [String]) -> String {
    let normalized = cells.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    return "| " + normalized.joined(separator: " | ") + " |"
}
