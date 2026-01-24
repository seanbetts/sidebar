import Foundation
import Markdown
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
public struct MarkdownImportResult {
    public let attributedString: AttributedString
    public let frontmatter: String?

    public init(attributedString: AttributedString, frontmatter: String?) {
        self.attributedString = attributedString
        self.frontmatter = frontmatter
    }
}

@available(iOS 26.0, macOS 26.0, *)
public struct MarkdownImporter {
    public init() {}

    public func attributedString(from markdown: String) -> MarkdownImportResult {
        let split = splitFrontmatter(from: markdown)
        let document = Document(parsing: split.body)
        var walker = MarkdownToAttributedStringWalker()
        walker.visit(document)
        return MarkdownImportResult(attributedString: walker.result, frontmatter: split.frontmatter)
    }
}

@available(iOS 26.0, macOS 26.0, *)
private struct MarkdownToAttributedStringWalker: MarkupWalker {
    var result = AttributedString()

    private var listStack: [(ordered: Bool, depth: Int)] = []
    private var blockquoteDepth: Int = 0

    mutating func visitDocument(_ document: Document) -> () {
        for child in document.children {
            visit(child)
        }
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> () {
        let plainText = paragraph.plainText.trimmed
        if plainText.hasPrefix(MarkdownRendering.imageCaptionMarker) {
            let caption = plainText
                .dropFirst(MarkdownRendering.imageCaptionMarker.count)
                .trimmingCharacters(in: .whitespaces)
            var captionText = AttributedString(String(caption))
            captionText.blockKind = .imageCaption
            captionText.font = DesignTokens.Typography.footnote
            captionText.foregroundColor = DesignTokens.Colors.textTertiary
            appendBlock(captionText)
            return
        }

        var paragraphText = AttributedString()
        for child in paragraph.children {
            paragraphText.append(inlineAttributedString(for: child))
        }

        if blockquoteDepth > 0 {
            paragraphText.blockKind = .blockquote
            paragraphText.foregroundColor = DesignTokens.Colors.textSecondary
        } else {
            paragraphText.blockKind = .paragraph
        }

        paragraphText.font = DesignTokens.Typography.body
        appendBlock(paragraphText)
    }

    mutating func visitHeading(_ heading: Heading) -> () {
        var headingText = AttributedString()
        for child in heading.children {
            headingText.append(inlineAttributedString(for: child))
        }

        switch heading.level {
        case 1:
            headingText.blockKind = .heading1
            headingText.font = .system(size: 32, weight: .bold)
        case 2:
            headingText.blockKind = .heading2
            headingText.font = .system(size: 24, weight: .semibold)
        case 3:
            headingText.blockKind = .heading3
            headingText.font = .system(size: 20, weight: .semibold)
        case 4:
            headingText.blockKind = .heading4
            headingText.font = .system(size: 18, weight: .semibold)
        case 5:
            headingText.blockKind = .heading5
            headingText.font = .system(size: 17, weight: .semibold)
        default:
            headingText.blockKind = .heading6
            headingText.font = .system(size: 16, weight: .semibold)
        }

        headingText.foregroundColor = DesignTokens.Colors.textPrimary
        appendBlock(headingText)
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> () {
        let depth = listStack.count + 1
        listStack.append((ordered: false, depth: depth))
        for item in unorderedList.listItems {
            visitListItem(item)
        }
        listStack.removeLast()
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> () {
        let depth = listStack.count + 1
        listStack.append((ordered: true, depth: depth))
        for item in orderedList.listItems {
            visitListItem(item)
        }
        listStack.removeLast()
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> () {
        blockquoteDepth += 1
        for child in blockQuote.children {
            visit(child)
        }
        blockquoteDepth = max(0, blockquoteDepth - 1)
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> () {
        var rule = AttributedString("---")
        rule.blockKind = .horizontalRule
        rule.foregroundColor = DesignTokens.Colors.border
        appendBlock(rule)
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> () {
        let language = codeBlock.language?.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = codeBlock.code.split(separator: "\n", omittingEmptySubsequences: false)

        for line in content {
            var lineText = AttributedString(String(line))
            lineText.blockKind = .codeBlock
            lineText.codeLanguage = language
            lineText.font = DesignTokens.Typography.monoBody
            lineText.foregroundColor = DesignTokens.Colors.textPrimary
            lineText.backgroundColor = DesignTokens.Colors.muted
            appendBlock(lineText)
        }
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> () {
        let raw = html.rawHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        var htmlText = AttributedString(raw)
        if raw.contains("image-gallery") {
            htmlText.blockKind = .gallery
        } else {
            htmlText.blockKind = .htmlBlock
        }
        htmlText.font = DesignTokens.Typography.monoBody
        htmlText.foregroundColor = DesignTokens.Colors.textSecondary
        appendBlock(htmlText)
    }

    private mutating func visitListItem(_ listItem: ListItem) {
        guard let context = listStack.last else { return }
        var itemText = AttributedString()

        for child in listItem.children {
            if let paragraph = child as? Paragraph {
                for inline in paragraph.children {
                    itemText.append(inlineAttributedString(for: inline))
                }
            }
        }

        if let checkbox = listItem.checkbox {
            let isChecked = checkbox == .checked
            itemText.blockKind = isChecked ? .taskChecked : .taskUnchecked
            if isChecked {
                itemText.strikethroughStyle = .single
                itemText.foregroundColor = DesignTokens.Colors.textSecondary
            }
        } else {
            itemText.blockKind = context.ordered ? .orderedList : .bulletList
        }

        itemText.listDepth = context.depth
        itemText.font = DesignTokens.Typography.body
        appendBlock(itemText)
    }

    private func inlineAttributedString(for markup: Markup) -> AttributedString {
        switch markup {
        case let text as Text:
            return AttributedString(text.string)
        case let softBreak as SoftBreak:
            return AttributedString(" ")
        case let lineBreak as LineBreak:
            return AttributedString("\n")
        case let emphasis as Emphasis:
            var inner = AttributedString()
            for child in emphasis.children {
                inner.append(inlineAttributedString(for: child))
            }
            let current = inner.inlinePresentationIntent ?? []
            inner.inlinePresentationIntent = current.union(.emphasized)
            return inner
        case let strong as Strong:
            var inner = AttributedString()
            for child in strong.children {
                inner.append(inlineAttributedString(for: child))
            }
            let current = inner.inlinePresentationIntent ?? []
            inner.inlinePresentationIntent = current.union(.stronglyEmphasized)
            return inner
        case let strike as Strikethrough:
            var inner = AttributedString()
            for child in strike.children {
                inner.append(inlineAttributedString(for: child))
            }
            inner.strikethroughStyle = .single
            return inner
        case let code as InlineCode:
            var inner = AttributedString(code.code)
            let current = inner.inlinePresentationIntent ?? []
            inner.inlinePresentationIntent = current.union(.code)
            inner.font = DesignTokens.Typography.monoBody
            inner.backgroundColor = DesignTokens.Colors.muted
            return inner
        case let link as Link:
            var inner = AttributedString()
            for child in link.children {
                inner.append(inlineAttributedString(for: child))
            }
            if let destination = URL(string: link.destination) {
                inner.link = destination
                inner.foregroundColor = .accentColor
                inner.underlineStyle = .single
            }
            return inner
        case let image as Image:
            return AttributedString("![\(image.plainText)](\(image.source))")
        case let html as InlineHTML:
            return AttributedString(html.rawHTML)
        default:
            var fallback = AttributedString()
            for child in markup.children {
                fallback.append(inlineAttributedString(for: child))
            }
            return fallback
        }
    }

    private mutating func appendBlock(_ block: AttributedString) {
        if !result.characters.isEmpty {
            result.append(AttributedString("\n"))
        }
        result.append(block)
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func splitFrontmatter(from markdown: String) -> (frontmatter: String?, body: String) {
    let trimmed = markdown.trimmed
    let marker = "---"
    guard trimmed.hasPrefix(marker) else {
        return (nil, markdown)
    }

    let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
    guard let first = lines.first, first.trimmed == marker else {
        return (nil, markdown)
    }

    var endIndex: Int?
    for (index, line) in lines.enumerated().dropFirst() where line.trimmed == marker {
        endIndex = index
        break
    }

    guard let endIndex else {
        return (nil, markdown)
    }

    let frontmatterLines = lines[0...endIndex].joined(separator: "\n")
    let bodyLines = lines.dropFirst(endIndex + 1).joined(separator: "\n")
    return (frontmatterLines, bodyLines)
}
