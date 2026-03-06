import Foundation

struct NotesSemanticDocument: Codable, Equatable {
    let version: Int
    let blocks: [Block]

    static let currentVersion = 1

    init(version: Int = currentVersion, blocks: [Block]) {
        self.version = version
        self.blocks = blocks
    }
}

extension NotesSemanticDocument {
    struct Block: Codable, Equatable {
        let type: BlockType
        let content: [InlineSegment]

        init(type: BlockType, content: [InlineSegment]) {
            self.type = type
            self.content = content
        }

        static func paragraph(_ content: [InlineSegment]) -> Block {
            Block(type: .paragraph, content: content)
        }
    }

    enum BlockType: String, Codable, CaseIterable {
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

    struct InlineSegment: Codable, Equatable {
        let text: String
        let marks: [InlineMark]

        init(text: String, marks: [InlineMark]) {
            self.text = text
            self.marks = marks
        }
    }

    enum InlineMark: String, Codable, CaseIterable {
        case bold
        case italic
        case underline

        static let storageOrder: [InlineMark] = [.bold, .italic, .underline]
    }
}
