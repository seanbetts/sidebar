@preconcurrency import Foundation
import Markdown
import sideBarShared
import SwiftUI

// MARK: - Inline Processing

extension MarkdownToAttributedStringWalker {
    // swiftlint:disable cyclomatic_complexity
    func inlineAttributedString(
        for markup: Markup,
        intents: InlinePresentationIntent = [],
        isStrikethrough: Bool = false
    ) -> AttributedString {
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
            return AttributedString("\n")
        case is LineBreak:
            return AttributedString("\n")
        case let emphasis as Emphasis:
            var inner = AttributedString()
            let mergedIntents = intents.union(.emphasized)
            for child in emphasis.children {
                inner.append(inlineAttributedString(for: child, intents: mergedIntents, isStrikethrough: isStrikethrough))
            }
            return wrapInlineMarkers(inner, prefix: "*", suffix: "*")
        case let strong as Strong:
            var inner = AttributedString()
            let mergedIntents = intents.union(.stronglyEmphasized)
            for child in strong.children {
                inner.append(inlineAttributedString(for: child, intents: mergedIntents, isStrikethrough: isStrikethrough))
            }
            return wrapInlineMarkers(inner, prefix: "**", suffix: "**")
        case let strike as Strikethrough:
            var inner = AttributedString()
            for child in strike.children {
                inner.append(inlineAttributedString(for: child, intents: intents, isStrikethrough: true))
            }
            return wrapInlineMarkers(inner, prefix: "~~", suffix: "~~")
        case let code as InlineCode:
            var inner = AttributedString(code.code)
            let range = fullRange(in: inner)
            let current = inner[range].inlinePresentationIntent ?? []
            inner[range].inlinePresentationIntent = current.union(.code).union(intents)
            inner[range].font = inlineCodeFont
            inner[range].backgroundColor = style.codeBackground
            if isStrikethrough {
                applyStrikethrough(to: &inner)
            }
            return wrapInlineMarkers(inner, prefix: "`", suffix: "`")
        case let link as Markdown.Link:
            var inner = AttributedString()
            for child in link.children {
                inner.append(inlineAttributedString(for: child, intents: intents, isStrikethrough: isStrikethrough))
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
            // swiftlint:disable:next todo
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
                fallback.append(inlineAttributedString(for: child, intents: intents, isStrikethrough: isStrikethrough))
            }
            return fallback
        }
    }
    // swiftlint:enable cyclomatic_complexity
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

    func applyStrikethrough(to text: inout AttributedString) {
        let range = fullRange(in: text)
        text[range].strikethroughStyle = .single
    }

    func adjustedSpacingBeforeIfNeeded(
        _ style: NSParagraphStyle,
        blockKind: BlockKind
    ) -> NSParagraphStyle {
        guard lastBlockKind.map(isHeading) == true, isParagraphOrList(blockKind) else {
            return style
        }
        let mutable = style.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
        mutable.paragraphSpacingBefore = 0
        return mutable
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

    func wrapInlineMarkers(
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
        to text: inout AttributedString,
        range: Range<AttributedString.Index>
    ) {
        text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
            .header(level: level),
            identity: level
        )
    }

    func applyListPresentationIntent(
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
