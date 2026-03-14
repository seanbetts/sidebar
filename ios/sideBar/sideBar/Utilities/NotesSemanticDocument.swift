import Foundation

public struct NotesSemanticDocument: Codable, Equatable {
    public let version: Int
    public let blocks: [Block]

    public static let currentVersion = 1

    public init(version: Int = currentVersion, blocks: [Block]) {
        self.version = version
        self.blocks = blocks
    }
}

enum NotesSemanticDocumentCodec {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()

    static func encode(_ document: NotesSemanticDocument) -> String? {
        guard let data = try? encoder.encode(document) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ content: String) -> NotesSemanticDocument? {
        guard let data = content.data(using: .utf8) else {
            return nil
        }
        return try? decoder.decode(NotesSemanticDocument.self, from: data)
    }
}

extension NotesSemanticDocument {
    public struct Block: Codable, Equatable {
        public let type: BlockType
        public let content: [InlineSegment]
        public let checked: Bool?

        public init(type: BlockType, content: [InlineSegment], checked: Bool? = nil) {
            self.type = type
            self.content = content
            self.checked = checked
        }

        public static func paragraph(_ content: [InlineSegment]) -> Block {
            Block(type: .paragraph, content: content)
        }
    }

    public enum BlockType: String, Codable, CaseIterable {
        case title
        case paragraph
        case heading
        case subheading
        case unorderedList = "unordered_list"
        case orderedList = "ordered_list"
        case checklist
        case listItem = "list_item"
        case blockquote
        case codeBlock = "code_block"
        case table
        case tableRow = "table_row"
        case tableCell = "table_cell"
        case media
        case caption
        case htmlBlock = "html_block"

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            if rawValue == "task_list" {
                self = .checklist
                return
            }
            guard let value = Self(rawValue: rawValue) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid NotesSemanticDocument.BlockType value: \(rawValue)"
                )
            }
            self = value
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    public struct InlineSegment: Codable, Equatable {
        public let text: String
        public let marks: [InlineMark]
        public let link: Link?

        public init(text: String, marks: [InlineMark], link: Link? = nil) {
            self.text = text
            self.marks = marks
            self.link = link
        }
    }

    public struct Link: Codable, Equatable {
        public let url: String

        public init(url: String) {
            self.url = url
        }
    }

    public enum InlineMark: String, Codable, CaseIterable {
        case bold
        case italic
        case underline
        case strikethrough
        case inlineCode = "inline_code"

        public static let storageOrder: [InlineMark] = [
            .bold,
            .italic,
            .underline,
            .strikethrough,
            .inlineCode
        ]
    }
}
