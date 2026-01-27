import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
public struct MarkdownExporter {
    public init() {}

    public func markdown(from attributedString: AttributedString, frontmatter: String? = nil) -> String {
        let body = exportBody(from: attributedString)
        return mergeFrontmatter(frontmatter, body: body)
    }
}

@available(iOS 26.0, macOS 26.0, *)
private struct ExportLineResult {
    let output: [String]
    let nextIndex: Int
    let isInCodeBlock: Bool
    let context: ExportLineContext?
}

@available(iOS 26.0, macOS 26.0, *)
private func exportBody(from attributedString: AttributedString) -> String {
    exportLines(in: attributedString).joined(separator: "\n")
}

@available(iOS 26.0, macOS 26.0, *)
private func mergeFrontmatter(_ frontmatter: String?, body: String) -> String {
    guard let frontmatter, !frontmatter.isEmpty else {
        return body
    }
    if body.isEmpty {
        return frontmatter
    }
    return frontmatter + "\n\n" + body
}

@available(iOS 26.0, macOS 26.0, *)
private func exportLines(in attributedString: AttributedString) -> [String] {
    let lines = splitLines(in: attributedString)
    var output: [String] = []
    var isInCodeBlock = false
    var lineIndex = 0
    var previousContext: ExportLineContext?

    while lineIndex < lines.count {
        if let tableResult = exportTableBlock(
            from: attributedString,
            lines: lines,
            startIndex: lineIndex,
            isInCodeBlock: &isInCodeBlock,
            previousContext: previousContext
        ) {
            output.append(contentsOf: tableResult.output)
            previousContext = tableResult.context
            lineIndex = tableResult.nextIndex
            continue
        }

        let lineResult = exportStandardLine(
            from: attributedString,
            lineRange: lines[lineIndex],
            lineIndex: lineIndex,
            isInCodeBlock: &isInCodeBlock,
            previousContext: previousContext
        )
        output.append(contentsOf: lineResult.output)
        previousContext = lineResult.context
        lineIndex = lineResult.nextIndex
    }

    closeCodeBlockIfNeeded(&isInCodeBlock, output: &output)
    return output
}

@available(iOS 26.0, macOS 26.0, *)
private func exportTableBlock(
    from attributedString: AttributedString,
    lines: [Range<AttributedString.Index>],
    startIndex: Int,
    isInCodeBlock: inout Bool,
    previousContext: ExportLineContext?
) -> ExportLineResult? {
    guard let tableBlock = tableBlock(from: attributedString, lines: lines, startIndex: startIndex) else {
        return nil
    }

    var output: [String] = []
    closeCodeBlockIfNeeded(&isInCodeBlock, output: &output)
    let currentContext = ExportLineContext.tableBlock()
    if shouldInsertBlankLine(
        previous: previousContext,
        current: currentContext,
        isSoftBreak: false
    ) {
        output.append("")
    }
    output.append(contentsOf: tableBlock.markdown)
    return ExportLineResult(
        output: output,
        nextIndex: tableBlock.nextIndex,
        isInCodeBlock: isInCodeBlock,
        context: currentContext
    )
}

@available(iOS 26.0, macOS 26.0, *)
private func exportStandardLine(
    from attributedString: AttributedString,
    lineRange: Range<AttributedString.Index>,
    lineIndex: Int,
    isInCodeBlock: inout Bool,
    previousContext: ExportLineContext?
) -> ExportLineResult {
    var output: [String] = []
    let lineText = String(attributedString[lineRange].characters)
    let blockKind = attributedString.blockKind(in: lineRange) ?? .paragraph

    if isInCodeBlock && blockKind != .codeBlock {
        closeCodeBlockIfNeeded(&isInCodeBlock, output: &output)
    }

    if blockKind == .blankLine {
        return ExportLineResult(
            output: output,
            nextIndex: lineIndex + 1,
            isInCodeBlock: isInCodeBlock,
            context: previousContext
        )
    }

    let listDepth = listDepth(in: attributedString, range: lineRange)
    let codeLanguage = codeLanguage(in: attributedString, range: lineRange)
    let currentContext = exportLineContext(
        attributedString: attributedString,
        lineRange: lineRange,
        lineText: lineText,
        blockKind: blockKind,
        listDepth: listDepth
    )
    if shouldInsertBlankLine(
        previous: previousContext,
        current: currentContext,
        isSoftBreak: false
    ) {
        output.append("")
    }

    appendLineOutput(
        to: &output,
        blockKind: blockKind,
        lineText: lineText,
        lineRange: lineRange,
        listDepth: listDepth,
        codeLanguage: codeLanguage,
        isInCodeBlock: &isInCodeBlock,
        attributedString: attributedString
    )

    return ExportLineResult(
        output: output,
        nextIndex: lineIndex + 1,
        isInCodeBlock: isInCodeBlock,
        context: currentContext
    )
}

@available(iOS 26.0, macOS 26.0, *)
private func exportLineContext(
    attributedString: AttributedString,
    lineRange: Range<AttributedString.Index>,
    lineText: String,
    blockKind: BlockKind,
    listDepth: Int?
) -> ExportLineContext {
    ExportLineContext(
        blockKind: blockKind,
        listDepth: listDepth,
        listIdentity: listIdentity(in: attributedString, range: lineRange),
        isListItem: isListItemBlockKind(blockKind),
        isBlockquote: isBlockquoteLine(blockKind: blockKind, lineText: lineText),
        isCodeBlock: blockKind == .codeBlock,
        isTableBlock: false
    )
}

@available(iOS 26.0, macOS 26.0, *)
private func appendLineOutput(
    to output: inout [String],
    blockKind: BlockKind,
    lineText: String,
    lineRange: Range<AttributedString.Index>,
    listDepth: Int?,
    codeLanguage: String?,
    isInCodeBlock: inout Bool,
    attributedString: AttributedString
) {
    switch blockKind {
    case .codeBlock:
        if !isInCodeBlock {
            let fence = codeLanguage.map { "```\($0)" } ?? "```"
            output.append(fence)
            isInCodeBlock = true
        }
        output.append(lineText)
    case .horizontalRule:
        output.append("---")
    case .gallery, .htmlBlock:
        output.append(lineText)
    case .imageCaption:
        output.append("\(MarkdownRendering.imageCaptionMarker) \(lineText)")
    default:
        let prefix = hasExistingBlockPrefix(blockKind: blockKind, lineText: lineText)
            ? ""
            : prefix(for: blockKind, listDepth: listDepth)
        let inlineMarkdown = serializeInline(attributedString[lineRange])
        output.append(prefix + inlineMarkdown)
    }
}

@available(iOS 26.0, macOS 26.0, *)
private struct ExportLineContext: Equatable {
    let blockKind: BlockKind
    let listDepth: Int?
    let listIdentity: Int?
    let isListItem: Bool
    let isBlockquote: Bool
    let isCodeBlock: Bool
    let isTableBlock: Bool

    static func tableBlock() -> ExportLineContext {
        ExportLineContext(
            blockKind: .htmlBlock,
            listDepth: nil,
            listIdentity: nil,
            isListItem: false,
            isBlockquote: false,
            isCodeBlock: false,
            isTableBlock: true
        )
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func splitLines(in text: AttributedString) -> [Range<AttributedString.Index>] {
    var lines: [Range<AttributedString.Index>] = []
    var lineStart = text.startIndex
    var current = text.startIndex

    while current < text.endIndex {
        if text.characters[current].isNewline {
            lines.append(lineStart..<current)
            lineStart = text.index(afterCharacter: current)
            current = lineStart
        } else {
            current = text.index(afterCharacter: current)
        }
    }

    if lineStart <= text.endIndex {
        lines.append(lineStart..<text.endIndex)
    }

    return lines
}

@available(iOS 26.0, macOS 26.0, *)
private func closeCodeBlockIfNeeded(_ isInCodeBlock: inout Bool, output: inout [String]) {
    if isInCodeBlock {
        output.append("```")
        isInCodeBlock = false
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func listDepth(in text: AttributedString, range: Range<AttributedString.Index>) -> Int? {
    var result: Int?
    for run in text[range].runs {
        guard let depth = run.listDepth else { continue }
        if result == nil {
            result = depth
        } else if result != depth {
            return nil
        }
    }
    return result
}

@available(iOS 26.0, macOS 26.0, *)
private func codeLanguage(in text: AttributedString, range: Range<AttributedString.Index>) -> String? {
    var result: String?
    for run in text[range].runs {
        guard let language = run.codeLanguage else { continue }
        if result == nil {
            result = language
        } else if result != language {
            return result
        }
    }
    return result
}

@available(iOS 26.0, macOS 26.0, *)
private func listIdentity(in text: AttributedString, range: Range<AttributedString.Index>) -> Int? {
    for run in text[range].runs {
        guard let intent = run[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] else { continue }
        for component in intent.components {
            switch component.kind {
            case .orderedList, .unorderedList:
                return component.identity
            default:
                break
            }
        }
    }
    return nil
}

@available(iOS 26.0, macOS 26.0, *)
private func isListItemBlockKind(_ blockKind: BlockKind) -> Bool {
    switch blockKind {
    case .bulletList, .orderedList, .taskChecked, .taskUnchecked:
        return true
    default:
        return false
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func isBlockquoteLine(blockKind: BlockKind, lineText: String) -> Bool {
    if blockKind == .blockquote {
        return true
    }
    let trimmed = lineText.trimmingCharacters(in: .whitespaces)
    return trimmed.hasPrefix(">")
}

@available(iOS 26.0, macOS 26.0, *)
@available(iOS 26.0, macOS 26.0, *)
private func shouldInsertBlankLine(
    previous: ExportLineContext?,
    current: ExportLineContext,
    isSoftBreak: Bool
) -> Bool {
    guard let previous else { return false }
    if isSoftBreak {
        return false
    }
    if previous.isCodeBlock && current.isCodeBlock {
        return false
    }
    if previous.isBlockquote && current.isBlockquote {
        return false
    }
    if previous.isListItem && current.isListItem {
        if let previousListId = previous.listIdentity, let currentListId = current.listIdentity {
            if previousListId == currentListId {
                return false
            }
        } else if previous.listDepth == current.listDepth {
            return false
        }
    }
    if previous.isTableBlock && current.isTableBlock {
        return false
    }
    return true
}

@available(iOS 26.0, macOS 26.0, *)
// swiftlint:disable cyclomatic_complexity
private func prefix(for blockKind: BlockKind, listDepth: Int?) -> String {
    let indent = String(repeating: "  ", count: max(0, (listDepth ?? 1) - 1))
    switch blockKind {
    case .heading1:
        return "# "
    case .heading2:
        return "## "
    case .heading3:
        return "### "
    case .heading4:
        return "#### "
    case .heading5:
        return "##### "
    case .heading6:
        return "###### "
    case .bulletList:
        return indent + "- "
    case .orderedList:
        return indent + "1. "
    case .taskChecked:
        return indent + "- [x] "
    case .taskUnchecked:
        return indent + "- [ ] "
    case .blockquote:
        return indent + "> "
    default:
        return ""
    }
}
// swiftlint:enable cyclomatic_complexity

@available(iOS 26.0, macOS 26.0, *)
private func serializeInline(_ attributed: AttributedSubstring) -> String {
    let lineText = String(attributed.characters)
    let hasInlineMarkers = lineHasInlineMarkers(lineText)
    var output = ""
    for run in attributed.runs {
        // Handle images first
        if let imageInfo = run.imageInfo {
            output += "![\(imageInfo.altText)](\(imageInfo.url.absoluteString))"
            continue
        }

        let text = String(attributed[run.range].characters)
        let intents = run.inlinePresentationIntent ?? []
        let isBold = intents.contains(.stronglyEmphasized)
        let isItalic = intents.contains(.emphasized)
        let isCode = intents.contains(.code)
        let isStrike = run.strikethroughStyle != nil
        let link = run.link

        var prefix = ""
        var suffix = ""

        if isCode {
            prefix += "`"
            suffix = "`" + suffix
        }
        if isStrike {
            prefix += "~~"
            suffix = "~~" + suffix
        }
        if isItalic {
            prefix += "*"
            suffix = "*" + suffix
        }
        if isBold {
            prefix += "**"
            suffix = "**" + suffix
        }

        if let link {
            output += "[\(text)](\(link.absoluteString))"
        } else if hasInlineMarkers {
            output += text
        } else {
            output += "\(prefix)\(text)\(suffix)"
        }
    }
    return output
}

@available(iOS 26.0, macOS 26.0, *)
private func lineHasInlineMarkers(_ lineText: String) -> Bool {
    let patterns = [
        #"\*\*[^*]+?\*\*"#,
        #"__[^_]+?__"#,
        #"~~[^~]+?~~"#,
        #"`[^`]+?`"#,
        #"\*[^*]+?\*"#,
        #"_[^_]+?_"#
    ]

    for pattern in patterns where lineText.range(of: pattern, options: .regularExpression) != nil {
        return true
    }

    return false
}

@available(iOS 26.0, macOS 26.0, *)
private func hasExistingBlockPrefix(blockKind: BlockKind, lineText: String) -> Bool {
    let trimmed = lineText.trimmingCharacters(in: .whitespaces)
    if let prefix = headingPrefix(for: blockKind) {
        return trimmed.hasPrefix(prefix)
    }
    if let pattern = blockPrefixPattern(for: blockKind) {
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }
    return false
}

@available(iOS 26.0, macOS 26.0, *)
private func headingPrefix(for blockKind: BlockKind) -> String? {
    switch blockKind {
    case .heading1: return "# "
    case .heading2: return "## "
    case .heading3: return "### "
    case .heading4: return "#### "
    case .heading5: return "##### "
    case .heading6: return "###### "
    default: return nil
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func blockPrefixPattern(for blockKind: BlockKind) -> String? {
    switch blockKind {
    case .bulletList:
        return #"^[-+*]\s"#
    case .orderedList:
        return #"^\d+\.\s"#
    case .taskChecked:
        return #"^[-+*]\s+\[[xX]\]\s"#
    case .taskUnchecked:
        return #"^[-+*]\s+\[\s\]\s"#
    case .blockquote:
        return #"^>\s"#
    default:
        return nil
    }
}

@available(iOS 26.0, macOS 26.0, *)
private struct TableBlock {
    let markdown: [String]
    let nextIndex: Int
}

@available(iOS 26.0, macOS 26.0, *)
private func tableBlock(
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
private struct TableRowInfo {
    let cells: [String]
    let isHeader: Bool
    let columnAlignments: [PresentationIntent.TableColumn.Alignment]?
}

@available(iOS 26.0, macOS 26.0, *)
private func tableRowInfo(in text: AttributedString, range: Range<AttributedString.Index>) -> TableRowInfo? {
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
private func splitCellRanges(
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
private func makeAlignmentRow(
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
private func renderTableRow(_ cells: [String]) -> String {
    let normalized = cells.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    return "| " + normalized.joined(separator: " | ") + " |"
}
