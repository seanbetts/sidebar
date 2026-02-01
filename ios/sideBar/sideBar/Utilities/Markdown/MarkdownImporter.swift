@preconcurrency import Foundation
import Markdown
import sideBarShared
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
    private let style: SideBarMarkdownStyle

    public init() {
        self.style = .default
    }

    public func attributedString(from markdown: String) -> MarkdownImportResult {
        let split = splitFrontmatter(from: markdown)
        let document = Document(parsing: split.body)
        var walker = MarkdownToAttributedStringWalker(style: style)
        walker.visit(document)
        return MarkdownImportResult(attributedString: walker.result, frontmatter: split.frontmatter)
    }
}

@available(iOS 26.0, macOS 26.0, *)
private struct MarkdownToAttributedStringWalker: MarkupWalker {
    var result = AttributedString()

    private struct ListStackEntry {
        var ordered: Bool
        var depth: Int
        var listId: Int
        var itemIndex: Int
    }

    private var listStack: [ListStackEntry] = []
    private var blockquoteDepth: Int = 0
    private var nextListId: Int = 1
    private let baseFontSize: CGFloat = 16
    private let inlineCodeFontSize: CGFloat = 14
    private let heading1FontSize: CGFloat = 32
    private let heading2FontSize: CGFloat = 24
    private let heading3FontSize: CGFloat = 20
    private let heading4FontSize: CGFloat = 18
    private let heading5FontSize: CGFloat = 17
    private let heading6FontSize: CGFloat = 16
    private let bodyFont = Font.system(size: 16)
    private let inlineCodeFont = Font.system(size: 14, weight: .regular, design: .monospaced)
    private let blockCodeFont = Font.system(size: 14, weight: .regular, design: .monospaced)
    private let style: SideBarMarkdownStyle

    init(style: SideBarMarkdownStyle) {
        self.style = style
    }

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
            captionText[fullRange(in: captionText)].paragraphStyle = paragraphStyle(
                lineSpacing: 0,
                spacingBefore: rem(0.25),
                spacingAfter: rem(0.75)
            )
            applyPresentationIntent(for: .imageCaption, to: &captionText)
            appendBlock(captionText)
            return
        }

        var paragraphText = AttributedString()
        for child in paragraph.children {
            paragraphText.append(inlineAttributedString(for: child))
        }

        if blockquoteDepth > 0 {
            paragraphText = prefixBlock(paragraphText, with: String(repeating: "> ", count: blockquoteDepth))
            applyBlockKind(.blockquote, to: &paragraphText)
            paragraphText[fullRange(in: paragraphText)].foregroundColor = DesignTokens.Colors.textSecondary
            paragraphText[fullRange(in: paragraphText)].paragraphStyle = paragraphStyle(
                lineSpacing: em(0.7, fontSize: baseFontSize),
                spacingBefore: em(1, fontSize: baseFontSize),
                spacingAfter: em(1, fontSize: baseFontSize),
                headIndent: em(1, fontSize: baseFontSize)
            )
        } else {
            applyBlockKind(.paragraph, to: &paragraphText)
            paragraphText[fullRange(in: paragraphText)].paragraphStyle = paragraphStyle(
                lineSpacing: em(0.2, fontSize: baseFontSize),
                spacingBefore: rem(0.5),
                spacingAfter: rem(0.5)
            )
        }

        paragraphText[fullRange(in: paragraphText)].font = bodyFont
        applyPresentationIntent(for: blockquoteDepth > 0 ? .blockquote : .paragraph, to: &paragraphText)
        appendBlock(paragraphText)
    }

    mutating func visitHeading(_ heading: Heading) {
        var headingText = AttributedString()
        for child in heading.children {
            headingText.append(inlineAttributedString(for: child))
        }
        let prefix = String(repeating: "#", count: heading.level) + " "
        headingText = prefixBlock(headingText, with: prefix)

        switch heading.level {
        case 1:
            applyBlockKind(.heading1, to: &headingText)
            headingText[fullRange(in: headingText)].font = .system(size: heading1FontSize, weight: .bold)
            headingText[fullRange(in: headingText)].paragraphStyle = paragraphStyle(
                lineSpacing: em(0.3, fontSize: heading1FontSize),
                spacingBefore: 0,
                spacingAfter: rem(0.3)
            )
        case 2:
            applyBlockKind(.heading2, to: &headingText)
            headingText[fullRange(in: headingText)].font = .system(size: heading2FontSize, weight: .semibold)
            headingText[fullRange(in: headingText)].paragraphStyle = paragraphStyle(
                lineSpacing: em(0.3, fontSize: heading2FontSize),
                spacingBefore: rem(1),
                spacingAfter: rem(0.3)
            )
        case 3:
            applyBlockKind(.heading3, to: &headingText)
            headingText[fullRange(in: headingText)].font = .system(size: heading3FontSize, weight: .semibold)
            headingText[fullRange(in: headingText)].paragraphStyle = paragraphStyle(
                lineSpacing: em(0.3, fontSize: heading3FontSize),
                spacingBefore: rem(1),
                spacingAfter: rem(0.3)
            )
        case 4:
            applyBlockKind(.heading4, to: &headingText)
            headingText[fullRange(in: headingText)].font = .system(size: heading4FontSize, weight: .semibold)
            headingText[fullRange(in: headingText)].paragraphStyle = paragraphStyle(
                lineSpacing: em(0.3, fontSize: heading4FontSize),
                spacingBefore: rem(1),
                spacingAfter: rem(0.3)
            )
        case 5:
            applyBlockKind(.heading5, to: &headingText)
            headingText[fullRange(in: headingText)].font = .system(size: heading5FontSize, weight: .semibold)
            headingText[fullRange(in: headingText)].paragraphStyle = paragraphStyle(
                lineSpacing: em(0.3, fontSize: heading5FontSize),
                spacingBefore: rem(1),
                spacingAfter: rem(0.3)
            )
        default:
            applyBlockKind(.heading6, to: &headingText)
            headingText[fullRange(in: headingText)].font = .system(size: heading6FontSize, weight: .semibold)
            headingText[fullRange(in: headingText)].paragraphStyle = paragraphStyle(
                lineSpacing: em(0.3, fontSize: heading6FontSize),
                spacingBefore: rem(1),
                spacingAfter: rem(0.3)
            )
        }

        headingText[fullRange(in: headingText)].foregroundColor = DesignTokens.Colors.textPrimary
        applyPresentationIntent(for: blockKindForHeading(level: heading.level), to: &headingText)
        appendBlock(headingText)
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
        let depth = listStack.count + 1
        let listId = nextListId
        nextListId += 1
        listStack.append(ListStackEntry(ordered: false, depth: depth, listId: listId, itemIndex: 0))
        let items = Array(unorderedList.listItems)
        for (index, item) in items.enumerated() {
            visitListItem(item, isFirst: index == 0, isLast: index == items.count - 1)
        }
        listStack.removeLast()
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) {
        let depth = listStack.count + 1
        let listId = nextListId
        nextListId += 1
        listStack.append(ListStackEntry(ordered: true, depth: depth, listId: listId, itemIndex: 0))
        let items = Array(orderedList.listItems)
        for (index, item) in items.enumerated() {
            visitListItem(item, isFirst: index == 0, isLast: index == items.count - 1)
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
        rule[fullRange(in: rule)].paragraphStyle = paragraphStyle(
            lineSpacing: 0,
            spacingBefore: rem(1.5),
            spacingAfter: rem(1.5)
        )
        applyPresentationIntent(for: .horizontalRule, to: &rule)
        appendBlock(rule)
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        let language = codeBlock.language?.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = codeBlock.code.split(separator: "\n", omittingEmptySubsequences: false)
        let totalLines = content.count

        for (index, line) in content.enumerated() {
            var lineText = AttributedString(String(line))
            applyBlockKind(.codeBlock, to: &lineText)
            lineText[fullRange(in: lineText)].codeLanguage = language
            lineText[fullRange(in: lineText)].font = blockCodeFont
            lineText[fullRange(in: lineText)].foregroundColor = DesignTokens.Colors.textPrimary
            lineText[fullRange(in: lineText)].backgroundColor = style.codeBlockBackground
            lineText[fullRange(in: lineText)].paragraphStyle = paragraphStyle(
                lineSpacing: em(0.5, fontSize: inlineCodeFontSize),
                spacingBefore: index == 0 ? rem(1) : 0,
                spacingAfter: index == totalLines - 1 ? rem(1) : 0,
                headIndent: DesignTokens.Spacing.md,
                tailIndent: DesignTokens.Spacing.md
            )
            applyPresentationIntent(for: .codeBlock, codeLanguage: language, to: &lineText)
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
        htmlText[fullRange(in: htmlText)].font = blockCodeFont
        htmlText[fullRange(in: htmlText)].foregroundColor = DesignTokens.Colors.textSecondary
        htmlText[fullRange(in: htmlText)].paragraphStyle = paragraphStyle(
            lineSpacing: em(0.2, fontSize: baseFontSize),
            spacingBefore: rem(0.5),
            spacingAfter: rem(0.5)
        )
        applyPresentationIntent(for: .htmlBlock, to: &htmlText)
        appendBlock(htmlText)
    }

    mutating func visitListItem(_ listItem: ListItem, isFirst: Bool, isLast: Bool) {
        guard !listStack.isEmpty else { return }
        listStack[listStack.count - 1].itemIndex += 1
        let context = listStack[listStack.count - 1]
        var itemText = AttributedString()
        var nestedBlocks: [Markup] = []

        for child in listItem.children {
            if let paragraph = child as? Paragraph {
                for inline in paragraph.children {
                    itemText.append(inlineAttributedString(for: inline))
                }
            } else {
                nestedBlocks.append(child)
            }
        }

        if !itemText.characters.isEmpty || listItem.checkbox != nil {
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

            let indent = String(repeating: "  ", count: max(0, context.depth - 1))
            let listPrefix: String
            if let checkbox = listItem.checkbox {
                let isChecked = checkbox == .checked
                listPrefix = indent + "- [" + (isChecked ? "x" : " ") + "] "
            } else if context.ordered {
                listPrefix = indent + "\(context.itemIndex). "
            } else {
                listPrefix = indent + "- "
            }
            let quotePrefix = blockquoteDepth > 0 ? String(repeating: "> ", count: blockquoteDepth) : ""
            itemText = prefixBlock(itemText, with: quotePrefix + listPrefix)

            itemText[fullRange(in: itemText)].listDepth = context.depth
            itemText[fullRange(in: itemText)].font = bodyFont
            let listIndentUnit = em(1.5, fontSize: baseFontSize)
            let listIndent = listIndentUnit * CGFloat(max(1, context.depth))
            let quoteIndent = blockquoteDepth > 0 ? em(1, fontSize: baseFontSize) : 0
            itemText[fullRange(in: itemText)].paragraphStyle = paragraphStyle(
                lineSpacing: em(0.2, fontSize: baseFontSize),
                spacingBefore: isFirst ? rem(0.5) : 0,
                spacingAfter: isLast ? rem(0.5) : 0,
                headIndent: listIndent + quoteIndent
            )
            applyPresentationIntent(
                for: itemText.blockKind(in: fullRange(in: itemText)) ?? .paragraph,
                listDepth: context.depth,
                listOrdinal: context.ordered ? context.itemIndex : nil,
                listId: context.listId,
                to: &itemText
            )
            appendBlock(itemText)
        }

        for nested in nestedBlocks {
            visit(nested)
        }
    }

    mutating func visitTable(_ table: Markdown.Table) {
        let alignments = table.columnAlignments
        let tableIntent = makeTableIntent(columnAlignments: alignments)

        var rowIndex = 0
        let rows = Array(table.body.rows)
        let totalRows = rows.count + 1
        appendTableRow(
            cells: table.head.children.compactMap { $0 as? Markdown.Table.Cell },
            rowIndex: rowIndex,
            isHeader: true,
            tableIntent: tableIntent,
            isFirst: true,
            isLast: totalRows == 1
        )
        rowIndex += 1

        for row in rows {
            let isLast = rowIndex == totalRows - 1
            appendTableRow(
                cells: row.children.compactMap { $0 as? Markdown.Table.Cell },
                rowIndex: rowIndex,
                isHeader: false,
                tableIntent: tableIntent,
                isFirst: false,
                isLast: isLast
            )
            rowIndex += 1
        }
    }

    // swiftlint:disable cyclomatic_complexity
    private func inlineAttributedString(for markup: Markup) -> AttributedString {
        switch markup {
        case let text as Markdown.Text:
            return AttributedString(text.string)
        case is SoftBreak:
            return AttributedString("\n")
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
            return wrapInlineMarkers(inner, prefix: "*", suffix: "*")
        case let strong as Strong:
            var inner = AttributedString()
            for child in strong.children {
                inner.append(inlineAttributedString(for: child))
            }
            let range = fullRange(in: inner)
            let current = inner[range].inlinePresentationIntent ?? []
            inner[range].inlinePresentationIntent = current.union(.stronglyEmphasized)
            return wrapInlineMarkers(inner, prefix: "**", suffix: "**")
        case let strike as Strikethrough:
            var inner = AttributedString()
            for child in strike.children {
                inner.append(inlineAttributedString(for: child))
            }
            inner[fullRange(in: inner)].strikethroughStyle = .single
            inner[fullRange(in: inner)].foregroundColor = DesignTokens.Colors.textSecondary
            return wrapInlineMarkers(inner, prefix: "~~", suffix: "~~")
        case let code as InlineCode:
            var inner = AttributedString(code.code)
            let range = fullRange(in: inner)
            let current = inner[range].inlinePresentationIntent ?? []
            inner[range].inlinePresentationIntent = current.union(.code)
            inner[range].font = inlineCodeFont
            inner[range].backgroundColor = style.codeBackground
            return wrapInlineMarkers(inner, prefix: "`", suffix: "`")
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
            // Store image info for round-trip, display as placeholder for now
            // TODO: Use AdaptiveImageGlyph when API is available
            var imageString = AttributedString("![\(alt)](\(source))")
            if let url = URL(string: source) {
                let range = fullRange(in: imageString)
                imageString[range].imageInfo = ImageInfo(url: url, altText: alt)
                imageString[range].foregroundColor = DesignTokens.Colors.textSecondary
            }
            return imageString
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

    private func prefixBlock(_ inner: AttributedString, with prefix: String) -> AttributedString {
        var result = AttributedString(prefix)
        result.append(inner)
        return result
    }

    private func wrapInlineMarkers(
        _ inner: AttributedString,
        prefix: String,
        suffix: String
    ) -> AttributedString {
        var prefixText = AttributedString(prefix)
        if !prefixText.characters.isEmpty {
            prefixText[prefixText.startIndex..<prefixText.endIndex].inlineMarker = true
        }
        var suffixText = AttributedString(suffix)
        if !suffixText.characters.isEmpty {
            suffixText[suffixText.startIndex..<suffixText.endIndex].inlineMarker = true
        }

        var result = prefixText
        result.append(inner)
        result.append(suffixText)
        return result
    }

    private func fullRange(in text: AttributedString) -> Range<AttributedString.Index> {
        text.startIndex..<text.endIndex
    }

    private func applyBlockKind(_ kind: BlockKind, to text: inout AttributedString) {
        let range = fullRange(in: text)
        text[range].blockKind = kind
    }

    private func applyPresentationIntent(
        for blockKind: BlockKind,
        listDepth: Int? = nil,
        listOrdinal: Int? = nil,
        listId: Int? = nil,
        codeLanguage: String? = nil,
        to text: inout AttributedString
    ) {
        let range = fullRange(in: text)
        if let headingLevel = headingLevel(for: blockKind) {
            applyHeadingIntent(level: headingLevel, to: &text, range: range)
            return
        }

        switch blockKind {
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6:
            return
        case .blockquote:
            let quoteIntent = PresentationIntent(.blockQuote, identity: 1)
            text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
                .paragraph,
                identity: 1,
                parent: quoteIntent
            )
        case .codeBlock:
            text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
                .codeBlock(languageHint: codeLanguage),
                identity: 1
            )
        case .horizontalRule:
            text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
                .thematicBreak,
                identity: 1
            )
        case .bulletList, .orderedList, .taskChecked, .taskUnchecked:
            applyListPresentationIntent(
                blockKind,
                listDepth: listDepth,
                listOrdinal: listOrdinal,
                listId: listId,
                to: &text,
                range: range
            )
        case .paragraph, .blankLine, .imageCaption, .gallery, .htmlBlock:
            text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(.paragraph, identity: 1)
        @unknown default:
            return
        }
    }

    private func headingLevel(for blockKind: BlockKind) -> Int? {
        switch blockKind {
        case .heading1: return 1
        case .heading2: return 2
        case .heading3: return 3
        case .heading4: return 4
        case .heading5: return 5
        case .heading6: return 6
        default: return nil
        }
    }

    private func applyHeadingIntent(
        level: Int,
        to text: inout AttributedString,
        range: Range<AttributedString.Index>
    ) {
        text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
            .header(level: level),
            identity: level
        )
    }

    private func applyListPresentationIntent(
        _ blockKind: BlockKind,
        listDepth: Int?,
        listOrdinal: Int?,
        listId: Int?,
        to text: inout AttributedString,
        range: Range<AttributedString.Index>
    ) {
        let listKind: PresentationIntent.Kind = blockKind == .orderedList ? .orderedList : .unorderedList
        let listIdentity = listId ?? (listDepth ?? 1)
        let listIntent = PresentationIntent(listKind, identity: listIdentity)
        let ordinal = listOrdinal ?? 1
        let listItemIntent = PresentationIntent(
            .listItem(ordinal: ordinal),
            identity: listIdentity * 1000 + ordinal,
            parent: listIntent
        )
        text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
            .paragraph,
            identity: 1,
            parent: listItemIntent
        )
        text[range][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = listDelimiter(for: blockKind)
    }

    private func listDelimiter(for blockKind: BlockKind) -> Character? {
        switch blockKind {
        case .bulletList:
            return "•"
        case .taskChecked:
            return "☑"
        case .taskUnchecked:
            return "☐"
        default:
            return nil
        }
    }

    private func blockKindForHeading(level: Int) -> BlockKind {
        switch level {
        case 1: return .heading1
        case 2: return .heading2
        case 3: return .heading3
        case 4: return .heading4
        case 5: return .heading5
        default: return .heading6
        }
    }

    private mutating func appendTableRow(
        cells: [Markdown.Table.Cell],
        rowIndex: Int,
        isHeader: Bool,
        tableIntent: PresentationIntent,
        isFirst: Bool,
        isLast: Bool
    ) {
        var rowText = AttributedString()
        for (index, cell) in cells.enumerated() {
            var cellText = AttributedString()
            for child in cell.children {
                cellText.append(inlineAttributedString(for: child))
            }

            let startIndex = rowText.endIndex
            rowText.append(cellText)
            let endIndex = rowText.endIndex
            let cellRange = startIndex..<endIndex
            applyTablePresentationIntent(
                to: &rowText,
                range: cellRange,
                rowIndex: rowIndex,
                columnIndex: index,
                isHeader: isHeader,
                tableIntent: tableIntent
            )

            if index < cells.count - 1 {
                rowText.append(AttributedString("\t"))
            }
        }

        let full = fullRange(in: rowText)
        rowText[full].font = bodyFont
        if isHeader {
            rowText[full].font = .system(size: 16, weight: .semibold)
            rowText[full].backgroundColor = DesignTokens.Colors.muted
        }
        rowText[full].paragraphStyle = paragraphStyle(
            lineSpacing: em(0.7, fontSize: baseFontSize),
            spacingBefore: isFirst ? rem(0.75) : 0,
            spacingAfter: isLast ? rem(0.75) : 0
        )
        if !isHeader && rowIndex % 2 == 1 {
            rowText[full].backgroundColor = DesignTokens.Colors.muted.opacity(0.4)
        }
        appendBlock(rowText)
    }

    private func applyTablePresentationIntent(
        to text: inout AttributedString,
        range: Range<AttributedString.Index>,
        rowIndex: Int,
        columnIndex: Int,
        isHeader: Bool,
        tableIntent: PresentationIntent
    ) {
        let rowKind: PresentationIntent.Kind = isHeader ? .tableHeaderRow : .tableRow(rowIndex: rowIndex)
        let rowIntent = PresentationIntent(rowKind, identity: rowIndex + 1, parent: tableIntent)
        let cellIntent = PresentationIntent(
            .tableCell(columnIndex: columnIndex),
            identity: (rowIndex + 1) * 1000 + columnIndex,
            parent: rowIntent
        )
        text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
            .paragraph,
            identity: 1,
            parent: cellIntent
        )
    }

    private func makeTableIntent(columnAlignments: [Markdown.Table.ColumnAlignment?]) -> PresentationIntent {
        let columns = columnAlignments.map { alignment -> PresentationIntent.TableColumn in
            let mapped: PresentationIntent.TableColumn.Alignment
            switch alignment {
            case .center:
                mapped = .center
            case .right:
                mapped = .right
            default:
                mapped = .left
            }
            return PresentationIntent.TableColumn(alignment: mapped)
        }
        return PresentationIntent(.table(columns: columns), identity: nextListId + 100)
    }

    private func unwrapOptionalString(_ value: String) -> String {
        value
    }

    private func unwrapOptionalString(_ value: String?) -> String {
        value ?? ""
    }

    private func rem(_ value: CGFloat) -> CGFloat {
        value * baseFontSize
    }

    private func em(_ value: CGFloat, fontSize: CGFloat) -> CGFloat {
        value * fontSize
    }

    private func paragraphStyle(
        lineSpacing: CGFloat,
        spacingBefore: CGFloat,
        spacingAfter: CGFloat,
        headIndent: CGFloat = 0,
        tailIndent: CGFloat = 0
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacingAfter
        style.headIndent = headIndent
        style.firstLineHeadIndent = headIndent
        if tailIndent != 0 {
            style.tailIndent = -tailIndent
        }
        return style
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
