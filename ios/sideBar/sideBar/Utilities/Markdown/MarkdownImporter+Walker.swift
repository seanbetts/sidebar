@preconcurrency import Foundation
import Markdown
import sideBarShared
import SwiftUI

struct MarkdownToAttributedStringWalker: MarkupWalker {
    var result = AttributedString()

    struct ListStackEntry {
        var ordered: Bool
        var depth: Int
        var listId: Int
        var itemIndex: Int
    }

    var listStack: [ListStackEntry] = []
    var blockquoteDepth: Int = 0
    var nextListId: Int = 1
    var lastBlockKind: BlockKind?
    let baseFontSize: CGFloat
    var inlineCodeFontSize: CGFloat {
        MarkdownTypography.inlineCodeFontSize(baseFontSize: baseFontSize)
    }
    var bodyFont: Font {
        Font.system(size: baseFontSize)
    }
    var inlineCodeFont: Font {
        Font.system(size: inlineCodeFontSize, weight: .regular, design: .monospaced)
    }
    var blockCodeFont: Font {
        Font.system(size: inlineCodeFontSize, weight: .regular, design: .monospaced)
    }
    let style: SideBarMarkdownStyle

    init(style: SideBarMarkdownStyle, baseFontSize: CGFloat = MarkdownTypography.defaultBodyFontSize) {
        self.style = style
        self.baseFontSize = baseFontSize
    }

    // MARK: - Block Visitors

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
            captionText[fullRange(in: captionText)].font = .system(
                size: MarkdownTypography.footnoteFontSize(baseFontSize: baseFontSize)
            )
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
            applyBlockKind(.blockquote, to: &paragraphText)
            paragraphText[fullRange(in: paragraphText)].foregroundColor = DesignTokens.Colors.textSecondary
            paragraphText[fullRange(in: paragraphText)].paragraphStyle = MarkdownParagraphMetrics.blockquoteParagraphStyle(
                baseFontSize: baseFontSize,
                headIndent: em(MarkdownParagraphMetrics.blockquoteIndentEm, fontSize: baseFontSize)
            )
        } else {
            applyBlockKind(.paragraph, to: &paragraphText)
            let paragraphStyle = MarkdownParagraphMetrics.bodyParagraphStyle(baseFontSize: baseFontSize)
            paragraphText[fullRange(in: paragraphText)].paragraphStyle = adjustedSpacingBeforeIfNeeded(
                paragraphStyle,
                blockKind: .paragraph
            )
        }

        paragraphText[fullRange(in: paragraphText)].font = bodyFont
        applyPresentationIntent(
            for: blockquoteDepth > 0 ? .blockquote : .paragraph,
            blockquoteDepth: blockquoteDepth,
            to: &paragraphText
        )
        appendBlock(paragraphText)
    }

    mutating func visitHeading(_ heading: Heading) {
        var headingText = AttributedString()
        for child in heading.children {
            headingText.append(inlineAttributedString(for: child))
        }

        let fontSize = MarkdownHeadingMetrics.fontSize(
            for: heading.level,
            baseFontSize: baseFontSize
        )
        let weight: Font.Weight = MarkdownHeadingMetrics.isBold(level: heading.level) ? .bold : .semibold
        let paragraphStyle = MarkdownHeadingMetrics.paragraphStyle(
            level: heading.level,
            baseFontSize: baseFontSize
        )

        switch heading.level {
        case 1:
            applyBlockKind(.heading1, to: &headingText)
        case 2:
            applyBlockKind(.heading2, to: &headingText)
        case 3:
            applyBlockKind(.heading3, to: &headingText)
        case 4:
            applyBlockKind(.heading4, to: &headingText)
        case 5:
            applyBlockKind(.heading5, to: &headingText)
        default:
            applyBlockKind(.heading6, to: &headingText)
        }

        headingText[fullRange(in: headingText)].font = .system(size: fontSize, weight: weight)
        headingText[fullRange(in: headingText)].paragraphStyle = paragraphStyle

        headingText[fullRange(in: headingText)].foregroundColor = DesignTokens.Colors.textPrimary
        applyPresentationIntent(
            for: blockKindForHeading(level: heading.level),
            blockquoteDepth: blockquoteDepth,
            to: &headingText
        )
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
            spacingBefore: rem(0.75),
            spacingAfter: rem(0.75)
        )
        applyPresentationIntent(for: .horizontalRule, to: &rule)
        appendBlock(rule)
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        let language = codeBlock.language?.trimmingCharacters(in: .whitespacesAndNewlines)
        var content = codeBlock.code.split(separator: "\n", omittingEmptySubsequences: false)
        if content.count > 1, content.last?.isEmpty == true {
            // Drop the parser's synthetic terminal split segment from the trailing newline
            // that precedes a closing fence.
            content.removeLast()
        }
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
        if raw == MarkdownBlankLineMarker.htmlComment {
            appendBlankLineBlock()
            return
        }
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

        let explicitTaskChecked = listItem.checkbox.map { $0 == .checked }
        let inferredTaskChecked = inferredTaskCheckedState(from: itemText)
        if explicitTaskChecked != nil || inferredTaskChecked != nil {
            itemText = stripTaskCheckboxPrefix(from: itemText)
        }

        if !itemText.characters.isEmpty || explicitTaskChecked != nil || inferredTaskChecked != nil {
            let blockKind = applyListItemBlockKind(
                to: &itemText,
                explicitTaskChecked: explicitTaskChecked,
                inferredTaskChecked: inferredTaskChecked,
                ordered: context.ordered
            )

            itemText[fullRange(in: itemText)].listDepth = context.depth
            itemText[fullRange(in: itemText)].font = bodyFont
            let listIndentUnit = em(1.5, fontSize: baseFontSize)
            let listIndent = listIndentUnit * CGFloat(max(1, context.depth))
            let quoteIndent = blockquoteDepth > 0 ? em(1, fontSize: baseFontSize) : 0
            let listStyle = MarkdownParagraphMetrics.listParagraphStyle(
                baseFontSize: baseFontSize,
                listDepth: context.depth,
                headIndent: listIndent + quoteIndent
            )
            itemText[fullRange(in: itemText)].paragraphStyle = adjustedSpacingBeforeIfNeeded(
                listStyle,
                blockKind: blockKind
            )
            applyPresentationIntent(
                for: blockKind,
                listDepth: context.depth,
                listOrdinal: context.ordered ? context.itemIndex : nil,
                listId: context.listId,
                blockquoteDepth: blockquoteDepth,
                to: &itemText
            )
            appendBlock(itemText)
        }

        for nested in nestedBlocks {
            visit(nested)
        }
    }

    func stripTaskCheckboxPrefix(from text: AttributedString) -> AttributedString {
        let raw = String(text.characters)
        guard let markerRange = raw.range(of: #"^\s*\[[ xX]\]\s+"#, options: .regularExpression) else {
            return text
        }
        let prefixLength = raw.distance(from: raw.startIndex, to: markerRange.upperBound)
        guard prefixLength > 0 else { return text }
        var trimmed = text
        let end = trimmed.index(trimmed.startIndex, offsetByCharacters: prefixLength)
        trimmed.removeSubrange(trimmed.startIndex..<end)
        return trimmed
    }

    func inferredTaskCheckedState(from text: AttributedString) -> Bool? {
        let raw = String(text.characters)
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("[x] ") || trimmed.hasPrefix("[X] ") {
            return true
        }
        if trimmed.hasPrefix("[ ] ") {
            return false
        }
        return nil
    }

    func applyListItemBlockKind(
        to text: inout AttributedString,
        explicitTaskChecked: Bool?,
        inferredTaskChecked: Bool?,
        ordered: Bool
    ) -> BlockKind {
        if let explicitTaskChecked {
            return applyTaskBlockKind(to: &text, isChecked: explicitTaskChecked)
        }
        if let inferredTaskChecked {
            return applyTaskBlockKind(to: &text, isChecked: inferredTaskChecked)
        }
        let blockKind: BlockKind = ordered ? .orderedList : .bulletList
        applyBlockKind(blockKind, to: &text)
        return blockKind
    }

    func applyTaskBlockKind(to text: inout AttributedString, isChecked: Bool) -> BlockKind {
        let blockKind: BlockKind = isChecked ? .taskChecked : .taskUnchecked
        applyBlockKind(blockKind, to: &text)
        if isChecked {
            applyStrikethrough(to: &text)
            text[fullRange(in: text)].foregroundColor = DesignTokens.Colors.textSecondary
        }
        return blockKind
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
}
