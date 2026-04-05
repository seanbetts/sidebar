import Foundation

public struct NotesSemanticDocument: Codable, Equatable {
    public let version: Int
    public let blocks: [Block]

    public static let currentVersion = 2

    public init(version: Int = currentVersion, blocks: [Block]) {
        self.version = Self.currentVersion
        self.blocks = Self.normalizedRootBlocks(blocks, sourceVersion: version)
    }

    enum CodingKeys: String, CodingKey {
        case version
        case blocks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        let blocks = try container.decode([Block].self, forKey: .blocks)

        switch version {
        case 1:
            self.init(version: version, blocks: Self.adaptVersionOneBlocks(blocks))
        case Self.currentVersion:
            self.init(version: version, blocks: blocks)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: container,
                debugDescription: "Unsupported NotesSemanticDocument version: \(version)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .version)
        try container.encode(blocks, forKey: .blocks)
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

private enum NotesSemanticDocumentBlockCodingKeys: String, CodingKey {
    case type
    case content
    case checked
    case children
}

extension NotesSemanticDocument {
    public struct Block: Codable, Equatable {
        public let type: BlockType
        public let content: [InlineSegment]
        public let checked: Bool?
        public let children: [Block]?

        public init(
            type: BlockType,
            content: [InlineSegment] = [],
            checked: Bool? = nil,
            children: [Block]? = nil
        ) {
            self.type = type
            self.content = content
            self.checked = checked
            self.children = children
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: NotesSemanticDocumentBlockCodingKeys.self)
            type = try container.decode(BlockType.self, forKey: .type)
            content = try container.decodeIfPresent(
                [InlineSegment].self,
                forKey: .content
            ) ?? []
            checked = try container.decodeIfPresent(Bool.self, forKey: .checked)
            children = try container.decodeIfPresent([Block].self, forKey: .children)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(
                keyedBy: NotesSemanticDocumentBlockCodingKeys.self
            )
            try container.encode(type, forKey: .type)
            if type.supportsInlineContent || !content.isEmpty {
                try container.encode(content, forKey: .content)
            }
            try container.encodeIfPresent(checked, forKey: .checked)
            try container.encodeIfPresent(children, forKey: .children)
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
        case divider
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

private extension NotesSemanticDocument {
    static let titleNormalizableBlockTypes: Set<BlockType> = [.paragraph, .heading, .subheading]
    static let rootContainerTypes: Set<BlockType> = [.orderedList, .unorderedList, .checklist, .blockquote]
    static let listContainerTypes: Set<BlockType> = [.orderedList, .unorderedList, .checklist]
    static let blockquoteChildTypes: Set<BlockType> = [
        .paragraph,
        .heading,
        .subheading,
        .orderedList,
        .unorderedList,
        .checklist,
        .codeBlock
    ]

    static func adaptVersionOneBlocks(_ blocks: [Block]) -> [Block] {
        blocks.map { block in
            switch block.type {
            case .orderedList, .unorderedList:
                return .init(
                    type: block.type,
                    children: [
                        .init(type: .listItem, content: block.content)
                    ]
                )
            case .checklist:
                return .init(
                    type: .checklist,
                    children: [
                        .init(
                            type: .listItem,
                            content: block.content,
                            checked: block.checked ?? false
                        )
                    ]
                )
            case .blockquote:
                return .init(
                    type: .blockquote,
                    children: [
                        .paragraph(block.content)
                    ]
                )
            default:
                return block
            }
        }
    }

    static func normalizedRootBlocks(
        _ blocks: [Block],
        sourceVersion _: Int
    ) -> [Block] {
        var normalized = blocks.compactMap { normalizedBlock($0, parent: nil) }
        guard !normalized.isEmpty else { return normalized }

        if titleNormalizableBlockTypes.contains(normalized[0].type) {
            normalized[0] = .init(type: .title, content: normalized[0].content)
        }

        return normalized
    }

    static func normalizedBlock(
        _ block: Block,
        parent: BlockType?
    ) -> Block? {
        switch block.type {
        case .title, .paragraph, .heading, .subheading, .codeBlock,
             .divider,
             .table, .tableRow, .tableCell, .media, .caption, .htmlBlock:
            if block.type == .divider {
                return .init(type: .divider)
            }
            return .init(type: block.type, content: block.content)
        case .listItem:
            guard let parent, listContainerTypes.contains(parent) else {
                return .paragraph(block.content)
            }
            return .init(
                type: .listItem,
                content: block.content,
                checked: parent == .checklist ? block.checked : nil
            )
        case .orderedList, .unorderedList, .checklist:
            let normalizedChildren = (block.children ?? []).compactMap { normalizedBlock($0, parent: block.type) }
                .filter { $0.type == .listItem }
            guard !normalizedChildren.isEmpty else { return nil }
            return .init(type: block.type, children: normalizedChildren)
        case .blockquote:
            let normalizedChildren = (block.children ?? []).compactMap { child -> Block? in
                guard blockquoteChildTypes.contains(child.type) || rootContainerTypes.contains(child.type) else {
                    return nil
                }
                return normalizedBlock(child, parent: .blockquote)
            }.filter { $0.type != .title && $0.type != .blockquote && $0.type != .listItem }
            guard !normalizedChildren.isEmpty else { return nil }
            return .init(type: .blockquote, children: normalizedChildren)
        }
    }
}

private extension NotesSemanticDocument.BlockType {
    var supportsInlineContent: Bool {
        switch self {
        case .divider, .orderedList, .unorderedList, .checklist, .blockquote:
            return false
        case .title, .paragraph, .heading, .subheading, .listItem, .codeBlock,
             .table, .tableRow, .tableCell, .media, .caption, .htmlBlock:
            return true
        }
    }
}
