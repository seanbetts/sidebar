import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
public struct MarkdownExporter {
    public init() {}

    public func markdown(from attributedString: AttributedString, frontmatter: String? = nil) -> String {
        let lines = splitLines(in: attributedString)
        var output: [String] = []
        var isInCodeBlock = false

        for lineRange in lines {
            let lineText = String(attributedString[lineRange].characters)
            let blockKind = attributedString.blockKind(in: lineRange) ?? .paragraph
            let listDepth = listDepth(in: attributedString, range: lineRange)
            let codeLanguage = codeLanguage(in: attributedString, range: lineRange)

            switch blockKind {
            case .codeBlock:
                if !isInCodeBlock {
                    let fence = codeLanguage.map { "```\($0)" } ?? "```"
                    output.append(fence)
                    isInCodeBlock = true
                }
                output.append(lineText)
            case .horizontalRule:
                closeCodeBlockIfNeeded(&isInCodeBlock, output: &output)
                output.append("---")
            case .gallery, .htmlBlock:
                closeCodeBlockIfNeeded(&isInCodeBlock, output: &output)
                output.append(lineText)
            case .imageCaption:
                closeCodeBlockIfNeeded(&isInCodeBlock, output: &output)
                output.append("\(MarkdownRendering.imageCaptionMarker) \(lineText)")
            default:
                closeCodeBlockIfNeeded(&isInCodeBlock, output: &output)
                let prefix = prefix(for: blockKind, listDepth: listDepth)
                let inlineMarkdown = serializeInline(attributedString[lineRange])
                output.append(prefix + inlineMarkdown)
            }
        }

        closeCodeBlockIfNeeded(&isInCodeBlock, output: &output)

        let body = output.joined(separator: "\n")
        guard let frontmatter, !frontmatter.isEmpty else {
            return body
        }
        if body.isEmpty {
            return frontmatter
        }
        return frontmatter + "\n\n" + body
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func splitLines(in text: AttributedString) -> [Range<AttributedString.Index>] {
    var lines: [Range<AttributedString.Index>] = []
    var lineStart = text.startIndex
    var current = text.startIndex

    while current < text.endIndex {
        if text.characters[current] == "\n" {
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

@available(iOS 26.0, macOS 26.0, *)
private func serializeInline(_ attributed: AttributedString) -> String {
    var output = ""
    for run in attributed.runs {
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
        } else {
            output += "\(prefix)\(text)\(suffix)"
        }
    }
    return output
}
