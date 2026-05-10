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

enum ChatToolActionKind: String, Equatable {
    case confirmation
    case undo
}

enum ChatToolActionStatus: String, Equatable {
    case pending
    case running
    case accepted
    case declined
    case undone
    case failed
}

struct ChatToolAction: Equatable, Identifiable {
    let id: String
    let kind: ChatToolActionKind
    let summary: String
    let toolName: String?
    let guardReason: String?
    let undoSupported: Bool
    let expiresAt: String?
    let entityType: String?
    let entityId: String?
    let status: ChatToolActionStatus
}

extension ChatToolAction {
    var confirmationPrompt: String {
        Self.confirmationPrompt(for: toolName)
    }

    var confirmationObjectName: String {
        guard let toolName = toolName?.trimmedOrNil,
              toolName.lowercased().hasPrefix("delete ") else {
            return "item"
        }
        let objectName = toolName
            .dropFirst("Delete ".count)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return objectName.isEmpty ? "item" : objectName
    }

    static func confirmationPrompt(for toolName: String?) -> String {
        guard let toolName = toolName?.trimmedOrNil,
              toolName.lowercased().hasPrefix("delete ") else {
            return "Please confirm this action."
        }
        let objectName = toolName
            .dropFirst("Delete ".count)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !objectName.isEmpty else {
            return "Please confirm this deletion."
        }
        return "Please confirm that you want to delete this \(objectName)."
    }
}

/// User decision for an inline destructive tool confirmation.
public enum ChatToolActionDecision: String, Codable {
    case accept
    case decline
}

struct ChatToolConfirmationRequestedPayload: Decodable {
    let confirmationId: String
    let toolCallId: String?
    let toolName: String
    let summary: String
    let guardReason: String?
    let undoSupported: Bool
    let expiresAt: String?

    private enum CodingKeys: String, CodingKey {
        case confirmationId = "confirmation_id"
        case toolCallId = "tool_call_id"
        case toolName = "tool_name"
        case summary
        case guardReason = "guard_reason"
        case undoSupported = "undo_supported"
        case expiresAt = "expires_at"
    }
}

struct ChatToolConfirmationResolvedPayload: Decodable {
    let confirmationId: String
    let decision: ChatToolActionDecision
    let resolvedAt: String?
    let assistantMessage: String?

    private enum CodingKeys: String, CodingKey {
        case confirmationId = "confirmation_id"
        case decision
        case resolvedAt = "resolved_at"
        case assistantMessage = "assistant_message"
    }
}

struct ChatUndoAvailablePayload: Decodable {
    let undoToken: String
    let summary: String
    let expiresAt: String?
    let entityType: String
    let entityId: String

    private enum CodingKeys: String, CodingKey {
        case undoToken = "undo_token"
        case summary
        case expiresAt = "expires_at"
        case entityType = "entity_type"
        case entityId = "entity_id"
    }
}
