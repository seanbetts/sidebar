import Foundation

enum NotesSemanticDocumentProjection {
    static let defaultTitle = "New Note"
    private static let maxTitleLength = 120

    static func plainText(from document: NotesSemanticDocument) -> String {
        document.blocks.map { block in
            switch block.type {
            case .paragraph:
                return block.content.map(\.text).joined()
            default:
                return ""
            }
        }
        .joined(separator: "\n")
    }

    static func title(from document: NotesSemanticDocument) -> String {
        title(fromPlainText: plainText(from: document))
    }

    static func title(fromPlainText plainText: String?) -> String {
        guard let plainText else { return defaultTitle }

        for line in plainText.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let normalized = stripMarkdownHeadingPrefix(from: trimmed)
            if normalized.isEmpty {
                continue
            }
            return String(normalized.prefix(maxTitleLength))
        }

        return defaultTitle
    }

    static func document(fromPlainText plainText: String) -> NotesSemanticDocument {
        if plainText.isEmpty {
            return NotesSemanticDocument(blocks: [.paragraph([.init(text: "", marks: [])])])
        }
        return NotesSemanticDocument(
            blocks: plainText.split(
                separator: "\n",
                omittingEmptySubsequences: false
            )
            .map { line in
                .paragraph([.init(text: String(line), marks: [])])
            }
        )
    }

    private static func stripMarkdownHeadingPrefix(from line: String) -> String {
        var hashes = 0
        var index = line.startIndex
        while index < line.endIndex, line[index] == "#", hashes < 6 {
            hashes += 1
            index = line.index(after: index)
        }

        guard hashes > 0, index < line.endIndex, line[index].isWhitespace else {
            return line
        }

        let stripped = line[index...].trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? line : stripped
    }
}
