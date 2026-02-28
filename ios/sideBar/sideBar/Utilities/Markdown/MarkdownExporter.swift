import Foundation
import SwiftUI

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
private struct OrderedListLevel {
    let key: String
    let depth: Int
    var ordinal: Int
}

@available(iOS 26.0, macOS 26.0, *)
private struct OrderedListState {
    var levels: [OrderedListLevel] = []

    mutating func reset() { levels.removeAll() }

    mutating func nextOrdinal(key: String, depth: Int) -> Int {
        trimToDepth(depth)
        if let index = levels.firstIndex(where: { $0.depth == depth && $0.key == key }) {
            levels[index].ordinal += 1
            trimAfter(index: index)
            return levels[index].ordinal
        }
        if let index = levels.firstIndex(where: { $0.depth == depth }) {
            levels[index] = OrderedListLevel(key: key, depth: depth, ordinal: 1)
            trimAfter(index: index)
            return 1
        }
        levels.append(OrderedListLevel(key: key, depth: depth, ordinal: 1))
        levels.sort { $0.depth < $1.depth }
        return 1
    }

    private mutating func trimToDepth(_ depth: Int) { levels.removeAll { $0.depth > depth } }

    private mutating func trimAfter(index: Int) { levels = Array(levels.prefix(index + 1)) }

    mutating func handleNonOrderedBlock(blockKind: BlockKind, listDepth: Int?) {
        switch blockKind {
        case .bulletList, .taskChecked, .taskUnchecked:
            let depth = max(1, listDepth ?? 1)
            levels.removeAll { $0.depth >= depth }
        case .orderedList:
            break
        default:
            reset()
        }
    }
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
    if body.isEmpty { return frontmatter }
    return frontmatter + "\n\n" + body
}

@available(iOS 26.0, macOS 26.0, *)
private func exportLines(in attributedString: AttributedString) -> [String] {
    let lines = splitLines(in: attributedString)
    var output: [String] = []
    var isInCodeBlock = false
    var lineIndex = 0
    var previousContext: ExportLineContext?
    var orderedListState = OrderedListState()

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
            previousContext: previousContext,
            orderedListState: &orderedListState
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
    previousContext: ExportLineContext?,
    orderedListState: inout OrderedListState
) -> ExportLineResult {
    var output: [String] = []
    let lineText = filteredText(from: attributedString[lineRange])
    let rawBlockKind = attributedString.blockKind(in: lineRange) ?? .paragraph
    let blockKind = normalizedBlockKind(rawBlockKind: rawBlockKind, lineText: lineText)

    if isInCodeBlock && blockKind != .codeBlock {
        closeCodeBlockIfNeeded(&isInCodeBlock, output: &output)
    }

    if blockKind == .blankLine {
        return ExportLineResult(
            output: output + [MarkdownBlankLineMarker.htmlComment],
            nextIndex: lineIndex + 1,
            isInCodeBlock: isInCodeBlock,
            context: ExportLineContext(path: .blankLine)
        )
    }

    let listDepth = listDepth(in: attributedString, range: lineRange)
    let listIdentity = listIdentity(in: attributedString, range: lineRange)
    let blockquoteDepth = blockquoteDepth(in: attributedString, range: lineRange)
    let listOrdinal = resolvedOrderedListOrdinal(
        blockKind: blockKind,
        listDepth: listDepth,
        listIdentity: listIdentity,
        blockquoteDepth: blockquoteDepth,
        orderedListState: &orderedListState
    )
    let codeLanguage = codeLanguage(in: attributedString, range: lineRange)
    let currentContext = exportLineContext(
        blockKind: blockKind,
        listDepth: listDepth,
        listIdentity: listIdentity,
        blockquoteDepth: blockquoteDepth
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
        listOrdinal: listOrdinal,
        blockquoteDepth: blockquoteDepth,
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
    blockKind: BlockKind,
    listDepth: Int?,
    listIdentity: Int?,
    blockquoteDepth: Int
) -> ExportLineContext {
    if blockKind == .codeBlock {
        return ExportLineContext(path: .codeBlock)
    }

    if let listContext = exportListContext(
        blockKind: blockKind,
        listDepth: listDepth,
        listIdentity: listIdentity,
        blockquoteDepth: blockquoteDepth
    ) {
        return ExportLineContext(path: .list(listContext))
    }

    if blockquoteDepth > 0 || blockKind == .blockquote {
        return ExportLineContext(path: .blockquote(depth: max(1, blockquoteDepth)))
    }

    return ExportLineContext(path: .other)
}

@available(iOS 26.0, macOS 26.0, *)
private func appendLineOutput(
    to output: inout [String],
    blockKind: BlockKind,
    lineText: String,
    lineRange: Range<AttributedString.Index>,
    listDepth: Int?,
    listOrdinal: Int?,
    blockquoteDepth: Int,
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
        let inlineMarkdown = serializeInline(attributedString[lineRange])
        let prefix = generatedPrefix(
            for: blockKind,
            listDepth: listDepth,
            listOrdinal: listOrdinal,
            blockquoteDepth: blockquoteDepth
        )
        output.append(prefix + inlineMarkdown)
    }
}

@available(iOS 26.0, macOS 26.0, *)
private struct ExportLineContext: Equatable {
    let path: ExportBlockPath

    static func tableBlock() -> ExportLineContext {
        ExportLineContext(path: .table)
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
private func normalizedBlockKind(rawBlockKind: BlockKind, lineText: String) -> BlockKind {
    if rawBlockKind == .paragraph && lineText.isEmpty {
        return .blankLine
    }
    return rawBlockKind
}

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
    switch (previous.path, current.path) {
    case (.blankLine, _), (_, .blankLine):
        return false
    case (.codeBlock, .codeBlock):
        return false
    case (.blockquote, .blockquote):
        return false
    case let (.list(previousList), .list(currentList)):
        return !isContinuingList(previous: previousList, current: currentList)
    case (.table, .table):
        return false
    default:
        break
    }

    return true
}

@available(iOS 26.0, macOS 26.0, *)
private func prefix(for blockKind: BlockKind, listDepth: Int?, listOrdinal: Int?) -> String {
    let indent = String(repeating: "  ", count: max(0, (listDepth ?? 1) - 1))
    let headingPrefixes: [BlockKind: String] = [
        .heading1: "# ",
        .heading2: "## ",
        .heading3: "### ",
        .heading4: "#### ",
        .heading5: "##### ",
        .heading6: "###### "
    ]
    if let headingPrefix = headingPrefixes[blockKind] {
        return headingPrefix
    }
    switch blockKind {
    case .bulletList:
        return indent + "- "
    case .orderedList:
        return indent + "\(max(1, listOrdinal ?? 1)). "
    case .taskChecked:
        return indent + "- [x] "
    case .taskUnchecked:
        return indent + "- [ ] "
    case .blockquote:
        return ""
    default:
        return ""
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func generatedPrefix(
    for blockKind: BlockKind,
    listDepth: Int?,
    listOrdinal: Int?,
    blockquoteDepth: Int
) -> String {
    let effectiveQuoteDepth = blockKind == .blockquote ? max(1, blockquoteDepth) : blockquoteDepth
    let quotePrefix = String(repeating: "> ", count: max(0, effectiveQuoteDepth))
    let basePrefix = prefix(for: blockKind, listDepth: listDepth, listOrdinal: listOrdinal)
    if blockKind == .blockquote {
        return quotePrefix
    }
    return quotePrefix + basePrefix
}

@available(iOS 26.0, macOS 26.0, *)
private func blockquoteDepth(in text: AttributedString, range: Range<AttributedString.Index>) -> Int {
    var maximumDepth = 0
    for run in text[range].runs {
        guard let intent = run[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] else {
            continue
        }
        let depth = intent.components.reduce(into: 0) { result, component in
            if case .blockQuote = component.kind {
                result += 1
            }
        }
        maximumDepth = max(maximumDepth, depth)
    }
    return maximumDepth
}

@available(iOS 26.0, macOS 26.0, *)
private func resolvedOrderedListOrdinal(
    blockKind: BlockKind,
    listDepth: Int?,
    listIdentity: Int?,
    blockquoteDepth: Int,
    orderedListState: inout OrderedListState
) -> Int? {
    guard blockKind == .orderedList else {
        orderedListState.handleNonOrderedBlock(blockKind: blockKind, listDepth: listDepth)
        return nil
    }

    let depth = max(1, listDepth ?? 1)
    let key = "\(listIdentity ?? 0):\(depth):\(blockquoteDepth)"
    return orderedListState.nextOrdinal(key: key, depth: depth)
}
