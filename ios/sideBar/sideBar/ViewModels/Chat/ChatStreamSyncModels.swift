import Foundation
import sideBarShared

struct ChatEntityChangedPayload: Decodable {
    let entityType: String
    let entityId: String
    let change: String
    let patch: [String: AnyCodable]?
    let invalidate: [String]
    let toolCallId: String?
    let conversationId: String?

    private enum CodingKeys: String, CodingKey {
        case entityType = "entity_type"
        case entityId = "entity_id"
        case change
        case patch
        case invalidate
        case toolCallId = "tool_call_id"
        case conversationId = "conversation_id"
    }
}

struct ChatEntityDeletedPayload: Decodable {
    let entityType: String
    let entityId: String
    let invalidate: [String]
    let toolCallId: String?
    let conversationId: String?

    private enum CodingKeys: String, CodingKey {
        case entityType = "entity_type"
        case entityId = "entity_id"
        case invalidate
        case toolCallId = "tool_call_id"
        case conversationId = "conversation_id"
    }
}

struct ChatCollectionInvalidatedPayload: Decodable {
    let targets: [String]
    let conversationId: String?
    let toolCallId: String?

    private enum CodingKeys: String, CodingKey {
        case targets
        case conversationId = "conversation_id"
        case toolCallId = "tool_call_id"
    }
}

struct ChatToolStatusPayload: Decodable {
    let name: String
    let status: String
    let toolCallId: String?
    let conversationId: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case displayName = "display_name"
        case status
        case toolCallId = "tool_call_id"
        case conversationId = "conversation_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let name = try container.decodeIfPresent(String.self, forKey: .name),
           !name.isEmpty {
            self.name = name
        } else {
            self.name = try container.decode(String.self, forKey: .displayName)
        }
        self.status = try container.decode(String.self, forKey: .status)
        self.toolCallId = try container.decodeIfPresent(String.self, forKey: .toolCallId)
        self.conversationId = try container.decodeIfPresent(String.self, forKey: .conversationId)
    }
}
