@preconcurrency import Foundation
import Markdown
import sideBarShared
import SwiftUI

// MARK: - Inline Processing

extension MarkdownToAttributedStringWalker {
    func inlineAttributedString(
        for markup: Markup,
        intents: InlinePresentationIntent = [],
        isStrikethrough: Bool = false
    ) -> AttributedString {
        if let simple = inlineSimpleAttributedString(
            for: markup,
            intents: intents,
            isStrikethrough: isStrikethrough
        ) {
            return simple
        }
        return inlineStyledAttributedString(
            for: markup,
            intents: intents,
            isStrikethrough: isStrikethrough
        )
    }

    private func inlineSimpleAttributedString(
        for markup: Markup,
        intents: InlinePresentationIntent,
        isStrikethrough: Bool
    ) -> AttributedString? {
        switch markup {
        case let text as Markdown.Text:
            var result = AttributedString(text.string)
            let range = fullRange(in: result)
            if !intents.isEmpty {
                result[range].inlinePresentationIntent = intents
            }
            if isStrikethrough {
                applyStrikethrough(to: &result)
            }
            return result
        case is SoftBreak:
            // Preserve authored single-line breaks as real editor lines.
            return AttributedString("\n")
        case is LineBreak:
            return AttributedString("\n")
        default:
            return nil
        }
    }

}

// MARK: - Block Helpers

extension MarkdownToAttributedStringWalker {
    mutating func appendBlock(_ block: AttributedString) {
        if !result.characters.isEmpty {
            result.append(AttributedString("\n"))
        }
        result.append(block)
        lastBlockKind = block.blockKind(in: fullRange(in: block))
    }

    mutating func appendBlankLineBlock() {
        if !result.characters.isEmpty {
            result.append(AttributedString("\n"))
        }
        lastBlockKind = .blankLine
    }

    func applyStrikethrough(to text: inout AttributedString) {
        let range = fullRange(in: text)
        text[range].strikethroughStyle = .single
    }

    func adjustedSpacingBeforeIfNeeded(
        _ style: NSParagraphStyle,
        blockKind: BlockKind
    ) -> NSParagraphStyle {
        _ = blockKind
        return style
    }

    func isHeading(_ blockKind: BlockKind) -> Bool {
        switch blockKind {
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6:
            return true
        default:
            return false
        }
    }

    func isParagraphOrList(_ blockKind: BlockKind) -> Bool {
        switch blockKind {
        case .paragraph, .bulletList, .orderedList, .taskChecked, .taskUnchecked:
            return true
        default:
            return false
        }
    }

    func prefixBlock(_ inner: AttributedString, with prefix: String) -> AttributedString {
        var result = AttributedString(prefix)
        result.append(inner)
        return result
    }

    func fullRange(in text: AttributedString) -> Range<AttributedString.Index> {
        text.startIndex..<text.endIndex
    }

    func applyBlockKind(_ kind: BlockKind, to text: inout AttributedString) {
        let range = fullRange(in: text)
        text[range].blockKind = kind
    }
}

// MARK: - Presentation Intent

extension MarkdownToAttributedStringWalker {
    func applyPresentationIntent(
        for blockKind: BlockKind,
        listDepth: Int? = nil,
        listOrdinal: Int? = nil,
        listId: Int? = nil,
        blockquoteDepth: Int = 0,
        codeLanguage: String? = nil,
        to text: inout AttributedString
    ) {
        let range = fullRange(in: text)
        if let headingLevel = headingLevel(for: blockKind) {
            applyHeadingIntent(
                level: headingLevel,
                blockquoteDepth: blockquoteDepth,
                to: &text,
                range: range
            )
            return
        }

        if isListBlockKind(blockKind) {
            applyListPresentationIntent(
                blockKind,
                listDepth: listDepth,
                listOrdinal: listOrdinal,
                listId: listId,
                blockquoteDepth: blockquoteDepth,
                to: &text,
                range: range
            )
            return
        }

        guard let intent = nonListPresentationIntent(
            for: blockKind,
            blockquoteDepth: blockquoteDepth,
            codeLanguage: codeLanguage
        ) else {
            return
        }
        text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = intent
    }

    func headingLevel(for blockKind: BlockKind) -> Int? {
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

    func applyHeadingIntent(
        level: Int,
        blockquoteDepth: Int,
        to text: inout AttributedString,
        range: Range<AttributedString.Index>
    ) {
        text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = scopedPresentationIntent(
            kind: .header(level: level),
            identity: level,
            blockquoteDepth: blockquoteDepth
        )
    }

    func applyListPresentationIntent(
        _ blockKind: BlockKind,
        listDepth: Int?,
        listOrdinal: Int?,
        listId: Int?,
        blockquoteDepth: Int,
        to text: inout AttributedString,
        range: Range<AttributedString.Index>
    ) {
        let listKind: PresentationIntent.Kind = blockKind == .orderedList ? .orderedList : .unorderedList
        let listIdentity = listId ?? (listDepth ?? 1)
        let listIntent: PresentationIntent
        if let quoteIntent = blockquoteIntent(depth: blockquoteDepth) {
            listIntent = PresentationIntent(listKind, identity: listIdentity, parent: quoteIntent)
        } else {
            listIntent = PresentationIntent(listKind, identity: listIdentity)
        }
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

    func listDelimiter(for blockKind: BlockKind) -> Character? {
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

    func blockKindForHeading(level: Int) -> BlockKind {
        switch level {
        case 1: return .heading1
        case 2: return .heading2
        case 3: return .heading3
        case 4: return .heading4
        case 5: return .heading5
        default: return .heading6
        }
    }

    func isListBlockKind(_ blockKind: BlockKind) -> Bool {
        switch blockKind {
        case .bulletList, .orderedList, .taskChecked, .taskUnchecked:
            return true
        default:
            return false
        }
    }

    func nonListPresentationIntent(
        for blockKind: BlockKind,
        blockquoteDepth: Int,
        codeLanguage: String?
    ) -> PresentationIntent? {
        switch blockKind {
        case .blockquote:
            return scopedPresentationIntent(
                kind: .paragraph,
                identity: 1,
                blockquoteDepth: blockquoteDepth,
                minimumBlockquoteDepth: 1
            )
        case .codeBlock:
            return scopedPresentationIntent(
                kind: .codeBlock(languageHint: codeLanguage),
                identity: 1,
                blockquoteDepth: blockquoteDepth
            )
        case .horizontalRule:
            return scopedPresentationIntent(
                kind: .thematicBreak,
                identity: 1,
                blockquoteDepth: blockquoteDepth
            )
        case .paragraph, .blankLine, .imageCaption, .gallery, .htmlBlock:
            return scopedPresentationIntent(
                kind: .paragraph,
                identity: 1,
                blockquoteDepth: blockquoteDepth
            )
        case .bulletList, .orderedList, .taskUnchecked, .taskChecked:
            return nil
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6:
            return nil
        }
    }

    func scopedPresentationIntent(
        kind: PresentationIntent.Kind,
        identity: Int,
        blockquoteDepth: Int,
        minimumBlockquoteDepth: Int = 0
    ) -> PresentationIntent {
        let depth = max(minimumBlockquoteDepth, blockquoteDepth)
        if let quoteIntent = blockquoteIntent(depth: depth) {
            return PresentationIntent(kind, identity: identity, parent: quoteIntent)
        }
        return PresentationIntent(kind, identity: identity)
    }

    func blockquoteIntent(depth: Int) -> PresentationIntent? {
        guard depth > 0 else { return nil }
        var current = PresentationIntent(.blockQuote, identity: 1)
        guard depth > 1 else { return current }
        for level in 2...depth {
            current = PresentationIntent(.blockQuote, identity: level, parent: current)
        }
        return current
    }
}

// MARK: - Table Rendering

extension MarkdownToAttributedStringWalker {
    mutating func appendTableRow(
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
            rowText[full].font = .system(size: baseFontSize, weight: .semibold)
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

    func applyTablePresentationIntent(
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

    func makeTableIntent(columnAlignments: [Markdown.Table.ColumnAlignment?]) -> PresentationIntent {
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
}

// MARK: - Utilities

extension MarkdownToAttributedStringWalker {
    func unwrapOptionalString(_ value: String) -> String {
        value
    }

    func unwrapOptionalString(_ value: String?) -> String {
        value ?? ""
    }

    func rem(_ value: CGFloat) -> CGFloat {
        value * baseFontSize
    }

    func em(_ value: CGFloat, fontSize: CGFloat) -> CGFloat {
        value * fontSize
    }

    func paragraphStyle(
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
