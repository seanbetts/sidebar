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

extension NotesSemanticDocument {
    public struct Block: Codable, Equatable {
        public let type: BlockType
        public let content: [InlineSegment]

        public init(type: BlockType, content: [InlineSegment]) {
            self.type = type
            self.content = content
        }

        public static func paragraph(_ content: [InlineSegment]) -> Block {
            Block(type: .paragraph, content: content)
        }
    }

    public enum BlockType: String, Codable, CaseIterable {
        case paragraph
        case heading
        case unorderedList = "unordered_list"
        case orderedList = "ordered_list"
        case taskList = "task_list"
        case listItem = "list_item"
        case blockquote
        case codeBlock = "code_block"
        case table
        case tableRow = "table_row"
        case tableCell = "table_cell"
        case media
        case caption
        case htmlBlock = "html_block"
    }

    public struct InlineSegment: Codable, Equatable {
        public let text: String
        public let marks: [InlineMark]

        public init(text: String, marks: [InlineMark]) {
            self.text = text
            self.marks = marks
        }
    }

    public enum InlineMark: String, Codable, CaseIterable {
        case bold
        case italic
        case underline

        public static let storageOrder: [InlineMark] = [.bold, .italic, .underline]
    }
}
