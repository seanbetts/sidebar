// swiftlint:disable file_length
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
    let lineText = filteredText(from: attributedString[lineRange])
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
private func prefix(for blockKind: BlockKind, listDepth: Int?) -> String {
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
    let indentedPrefixes: [BlockKind: String] = [
        .bulletList: "- ",
        .orderedList: "1. ",
        .taskChecked: "- [x] ",
        .taskUnchecked: "- [ ] ",
        .blockquote: "> "
    ]
    if let indentedPrefix = indentedPrefixes[blockKind] {
        return indent + indentedPrefix
    }
    return ""
}

@available(iOS 26.0, macOS 26.0, *)
func serializeInline(_ attributed: AttributedSubstring) -> String {
    let lineText = filteredText(from: attributed)
    let hasInlineMarkers = lineHasInlineMarkers(lineText)
    var output = ""
    for run in attributed.runs {
        if run.listMarker == true {
            continue
        }
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
private func filteredText(from attributed: AttributedSubstring) -> String {
    var result = ""
    for run in attributed.runs {
        if run.listMarker == true {
            continue
        }
        result += String(attributed[run.range].characters)
    }
    return result
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
