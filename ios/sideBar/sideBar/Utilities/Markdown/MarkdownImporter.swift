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

    mutating func visitDocument(_ document: Document) {
        for child in document.children {
            visit(child)
        }
    }

    mutating func visitParagraph(_ paragraph: Paragraph) {
        let plainText = paragraph.plainText.trimmed
        if plainText.hasPrefix(MarkdownRendering.imageCaptionMarker) {
            let caption = plainText
                .dropFirst(MarkdownRendering.imageCaptionMarker.count)
                .trimmingCharacters(in: .whitespaces)
            var captionText = AttributedString(String(caption))
            applyBlockKind(.imageCaption, to: &captionText)
            captionText[fullRange(in: captionText)].font = DesignTokens.Typography.footnote
            captionText[fullRange(in: captionText)].foregroundColor = DesignTokens.Colors.textTertiary
            appendBlock(captionText)
            return
        }

        var paragraphText = AttributedString()
        for child in paragraph.children {
            paragraphText.append(inlineAttributedString(for: child))
        }

        if blockquoteDepth > 0 {
            applyBlockKind(.blockquote, to: &paragraphText)
            paragraphText[fullRange(in: paragraphText)].foregroundColor = DesignTokens.Colors.textSecondary
        } else {
            applyBlockKind(.paragraph, to: &paragraphText)
        }

        paragraphText[fullRange(in: paragraphText)].font = DesignTokens.Typography.body
        appendBlock(paragraphText)
    }

    mutating func visitHeading(_ heading: Heading) {
        var headingText = AttributedString()
        for child in heading.children {
            headingText.append(inlineAttributedString(for: child))
        }

        switch heading.level {
        case 1:
            applyBlockKind(.heading1, to: &headingText)
            headingText[fullRange(in: headingText)].font = .system(size: 32, weight: .bold)
        case 2:
            applyBlockKind(.heading2, to: &headingText)
            headingText[fullRange(in: headingText)].font = .system(size: 24, weight: .semibold)
        case 3:
            applyBlockKind(.heading3, to: &headingText)
            headingText[fullRange(in: headingText)].font = .system(size: 20, weight: .semibold)
        case 4:
            applyBlockKind(.heading4, to: &headingText)
            headingText[fullRange(in: headingText)].font = .system(size: 18, weight: .semibold)
        case 5:
            applyBlockKind(.heading5, to: &headingText)
            headingText[fullRange(in: headingText)].font = .system(size: 17, weight: .semibold)
        default:
            applyBlockKind(.heading6, to: &headingText)
            headingText[fullRange(in: headingText)].font = .system(size: 16, weight: .semibold)
        }

        headingText[fullRange(in: headingText)].foregroundColor = DesignTokens.Colors.textPrimary
        appendBlock(headingText)
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
        let depth = listStack.count + 1
        listStack.append((ordered: false, depth: depth))
        for item in unorderedList.listItems {
            visitListItem(item)
        }
        listStack.removeLast()
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) {
        let depth = listStack.count + 1
        listStack.append((ordered: true, depth: depth))
        for item in orderedList.listItems {
            visitListItem(item)
        }
        listStack.removeLast()
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        blockquoteDepth += 1
        for child in blockQuote.children {
            visit(child)
        }
        blockquoteDepth = max(0, blockquoteDepth - 1)
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        var rule = AttributedString("---")
        applyBlockKind(.horizontalRule, to: &rule)
        rule[fullRange(in: rule)].foregroundColor = DesignTokens.Colors.border
        appendBlock(rule)
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        let language = codeBlock.language?.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = codeBlock.code.split(separator: "\n", omittingEmptySubsequences: false)

        for line in content {
            var lineText = AttributedString(String(line))
            applyBlockKind(.codeBlock, to: &lineText)
            lineText[fullRange(in: lineText)].codeLanguage = language
            lineText[fullRange(in: lineText)].font = DesignTokens.Typography.monoBody
            lineText[fullRange(in: lineText)].foregroundColor = DesignTokens.Colors.textPrimary
            lineText[fullRange(in: lineText)].backgroundColor = DesignTokens.Colors.muted
            appendBlock(lineText)
        }
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) {
        let raw = html.rawHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        var htmlText = AttributedString(raw)
        if raw.contains("image-gallery") {
            applyBlockKind(.gallery, to: &htmlText)
        } else {
            applyBlockKind(.htmlBlock, to: &htmlText)
        }
        htmlText[fullRange(in: htmlText)].font = DesignTokens.Typography.monoBody
        htmlText[fullRange(in: htmlText)].foregroundColor = DesignTokens.Colors.textSecondary
        appendBlock(htmlText)
    }

    mutating func visitListItem(_ listItem: ListItem) {
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
            applyBlockKind(isChecked ? .taskChecked : .taskUnchecked, to: &itemText)
            if isChecked {
                itemText[fullRange(in: itemText)].strikethroughStyle = .single
                itemText[fullRange(in: itemText)].foregroundColor = DesignTokens.Colors.textSecondary
            }
        } else {
            applyBlockKind(context.ordered ? .orderedList : .bulletList, to: &itemText)
        }

        itemText[fullRange(in: itemText)].listDepth = context.depth
        itemText[fullRange(in: itemText)].font = DesignTokens.Typography.body
        appendBlock(itemText)
    }

    // swiftlint:disable cyclomatic_complexity
    private func inlineAttributedString(for markup: Markup) -> AttributedString {
        switch markup {
        case let text as Markdown.Text:
            return AttributedString(text.string)
        case is SoftBreak:
            return AttributedString(" ")
        case is LineBreak:
            return AttributedString("\n")
        case let emphasis as Emphasis:
            var inner = AttributedString()
            for child in emphasis.children {
                inner.append(inlineAttributedString(for: child))
            }
            let range = fullRange(in: inner)
            let current = inner[range].inlinePresentationIntent ?? []
            inner[range].inlinePresentationIntent = current.union(.emphasized)
            return inner
        case let strong as Strong:
            var inner = AttributedString()
            for child in strong.children {
                inner.append(inlineAttributedString(for: child))
            }
            let range = fullRange(in: inner)
            let current = inner[range].inlinePresentationIntent ?? []
            inner[range].inlinePresentationIntent = current.union(.stronglyEmphasized)
            return inner
        case let strike as Strikethrough:
            var inner = AttributedString()
            for child in strike.children {
                inner.append(inlineAttributedString(for: child))
            }
            inner[fullRange(in: inner)].strikethroughStyle = .single
            return inner
        case let code as InlineCode:
            var inner = AttributedString(code.code)
            let range = fullRange(in: inner)
            let current = inner[range].inlinePresentationIntent ?? []
            inner[range].inlinePresentationIntent = current.union(.code)
            inner[range].font = DesignTokens.Typography.monoBody
            inner[range].backgroundColor = DesignTokens.Colors.muted
            return inner
        case let link as Markdown.Link:
            var inner = AttributedString()
            for child in link.children {
                inner.append(inlineAttributedString(for: child))
            }
            if let destination = link.destination,
               let url = URL(string: destination) {
                inner[fullRange(in: inner)].link = url
                inner[fullRange(in: inner)].foregroundColor = .accentColor
                inner[fullRange(in: inner)].underlineStyle = .single
            }
            return inner
        case let image as Markdown.Image:
            let alt = unwrapOptionalString(image.plainText)
            let source = unwrapOptionalString(image.source)
            return AttributedString("![\(alt)](\(source))")
        case let html as Markdown.InlineHTML:
            return AttributedString(html.rawHTML)
        default:
            var fallback = AttributedString()
            for child in markup.children {
                fallback.append(inlineAttributedString(for: child))
            }
            return fallback
        }
    }
    // swiftlint:enable cyclomatic_complexity

    private mutating func appendBlock(_ block: AttributedString) {
        if !result.characters.isEmpty {
            result.append(AttributedString("\n"))
        }
        result.append(block)
    }

    private func fullRange(in text: AttributedString) -> Range<AttributedString.Index> {
        text.startIndex..<text.endIndex
    }

    private func applyBlockKind(_ kind: BlockKind, to text: inout AttributedString) {
        let range = fullRange(in: text)
        text[range].blockKind = kind
    }

    private func unwrapOptionalString(_ value: String) -> String {
        value
    }

    private func unwrapOptionalString(_ value: String?) -> String {
        value ?? ""
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
