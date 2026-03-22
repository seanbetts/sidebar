import Foundation

enum NotesSemanticDocumentProjection {
    static let defaultTitle = "New Note"
    private static let maxTitleLength = 120

    static func plainText(from document: NotesSemanticDocument) -> String {
        projectedLines(for: document.blocks).joined(separator: "\n")
    }

    static func title(from document: NotesSemanticDocument) -> String {
        guard let firstBlock = document.blocks.first, firstBlock.type == .title else {
            return defaultTitle
        }
        let trimmed = inlineText(from: firstBlock.content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return defaultTitle
        }
        return String(trimmed.prefix(maxTitleLength))
    }

    static func title(fromPlainText plainText: String?) -> String {
        guard let plainText else { return defaultTitle }

        for line in plainText.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            return String(trimmed.prefix(maxTitleLength))
        }

        return defaultTitle
    }

    static func document(fromPlainText plainText: String) -> NotesSemanticDocument {
        if plainText.isEmpty {
            return NotesSemanticDocument(
                blocks: [.init(type: .title, content: [.init(text: "", marks: [])])]
            )
        }
        let lines = plainText.split(separator: "\n", omittingEmptySubsequences: false)
        var blocks: [NotesSemanticDocument.Block] = [
            .init(type: .title, content: [.init(text: String(lines.first ?? ""), marks: [])])
        ]
        blocks.append(
            contentsOf: lines.dropFirst().map { line in
                .paragraph([.init(text: String(line), marks: [])])
            }
        )
        return NotesSemanticDocument(blocks: blocks)
    }

    private static func projectedLines(
        for blocks: [NotesSemanticDocument.Block],
        quotePrefix: String = ""
    ) -> [String] {
        blocks.enumerated().flatMap { index, block in
            projectedLines(for: block, orderedIndex: index, quotePrefix: quotePrefix)
        }
    }

    private static func projectedLines(
        for block: NotesSemanticDocument.Block,
        orderedIndex: Int,
        quotePrefix: String
    ) -> [String] {
        switch block.type {
        case .title, .paragraph, .heading, .subheading, .listItem, .codeBlock:
            return prefixedLines(inlineText(from: block.content), prefix: quotePrefix)
        case .orderedList:
            return (block.children ?? []).enumerated().flatMap { itemIndex, child in
                projectedListItemLines(
                    for: child,
                    prefix: "\(quotePrefix)\(itemIndex + 1). "
                )
            }
        case .unorderedList:
            return (block.children ?? []).flatMap { child in
                projectedListItemLines(for: child, prefix: "\(quotePrefix)- ")
            }
        case .checklist:
            return (block.children ?? []).flatMap { child in
                let marker = child.checked == true ? "x" : " "
                return projectedListItemLines(for: child, prefix: "\(quotePrefix)- [\(marker)] ")
            }
        case .blockquote:
            return projectedLines(for: block.children ?? [], quotePrefix: "\(quotePrefix)> ")
        case .table, .tableRow, .tableCell, .media, .caption, .htmlBlock:
            assertionFailure("Unsupported block type for plain-text projection: \(block.type.rawValue)")
            return []
        }
    }

    private static func projectedListItemLines(
        for block: NotesSemanticDocument.Block,
        prefix: String
    ) -> [String] {
        let lines = prefixedLines(inlineText(from: block.content), prefix: prefix)
        return lines.isEmpty ? [prefix.trimmingCharacters(in: .whitespaces)] : lines
    }

    private static func prefixedLines(
        _ content: String,
        prefix: String
    ) -> [String] {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard !lines.isEmpty else { return [prefix] }
        return lines.map { "\(prefix)\($0)" }
    }

    private static func inlineText(from content: [NotesSemanticDocument.InlineSegment]) -> String {
        content.map { segment in
            if !segment.text.isEmpty {
                return segment.text
            }
            return segment.link?.url ?? ""
        }.joined()
    }
}
