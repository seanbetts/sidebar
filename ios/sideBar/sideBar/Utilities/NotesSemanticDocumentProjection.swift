import Foundation

enum NotesSemanticDocumentProjection {
    static let defaultTitle = "New Note"
    private static let maxTitleLength = 120

    static func plainText(from document: NotesSemanticDocument) -> String {
        var orderedIndex = 0
        return document.blocks.map { block in
            let projected = projectedText(for: block, orderedIndex: orderedIndex)
            if block.type == .orderedList {
                orderedIndex += 1
            } else {
                orderedIndex = 0
            }
            return projected
        }.joined(separator: "\n")
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

    private static func projectedText(for block: NotesSemanticDocument.Block, orderedIndex: Int) -> String {
        let content = inlineText(from: block.content)
        switch block.type {
        case .title, .paragraph, .heading, .subheading, .listItem, .codeBlock:
            return content
        case .unorderedList:
            return "- \(content)"
        case .orderedList:
            return "\(orderedIndex + 1). \(content)"
        case .checklist:
            return "- [\(block.checked == true ? "x" : " ")] \(content)"
        case .blockquote:
            return "> \(content)"
        case .table, .tableRow, .tableCell, .media, .caption, .htmlBlock:
            assertionFailure("Unsupported block type for plain-text projection: \(block.type.rawValue)")
            return ""
        }
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
