import Foundation
import sideBarShared

/// Represents a message role enum.
public enum MessageRole: String, Codable {
    case user
    case assistant

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self))?.lowercased() ?? ""
        self = MessageRole(rawValue: rawValue) ?? .assistant
    }
}

/// Represents a message status enum.
public enum MessageStatus: String, Codable {
    case pending
    case streaming
    case complete
    case error

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self))?.lowercased() ?? ""
        switch rawValue {
        case MessageStatus.pending.rawValue:
            self = .pending
        case MessageStatus.streaming.rawValue:
            self = .streaming
        case MessageStatus.error.rawValue:
            self = .error
        case "completed":
            self = .complete
        default:
            self = .complete
        }
    }
}

/// Represents a tool call struct.
public struct ToolCall: Codable, Identifiable {
    /// The id value.
    public let id: String
    /// The name value.
    public let name: String
    /// The parameters value.
    public let parameters: [String: AnyCodable]
    /// The status value.
    public let status: ToolStatus
    /// The result value.
    public let result: AnyCodable?
    /// Optional canonical skill ID for icon and metadata lookup.
    public let skillId: String?
    /// Optional icon key (currently aligned to skill ID).
    public let iconKey: String?

    public init(
        id: String,
        name: String,
        parameters: [String: AnyCodable],
        status: ToolStatus,
        result: AnyCodable? = nil,
        skillId: String? = nil,
        iconKey: String? = nil
    ) {
        self.id = id
        self.name = name
        self.parameters = parameters
        self.status = status
        self.result = result
        self.skillId = skillId
        self.iconKey = iconKey
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case parameters
        case status
        case result
        case skillId
        case iconKey
        case legacySkillId = "skill_id"
        case legacyIconKey = "icon_key"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        parameters = (try? container.decode([String: AnyCodable].self, forKey: .parameters)) ?? [:]
        status = (try? container.decode(ToolStatus.self, forKey: .status)) ?? .pending
        result = try? container.decodeIfPresent(AnyCodable.self, forKey: .result)
        skillId = try container.decodeIfPresent(String.self, forKey: .skillId)
            ?? container.decodeIfPresent(String.self, forKey: .legacySkillId)
        iconKey = try container.decodeIfPresent(String.self, forKey: .iconKey)
            ?? container.decodeIfPresent(String.self, forKey: .legacyIconKey)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(parameters, forKey: .parameters)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(result, forKey: .result)
        try container.encodeIfPresent(skillId, forKey: .skillId)
        try container.encodeIfPresent(iconKey, forKey: .iconKey)
    }
}

/// Represents a tool status enum.
public enum ToolStatus: String, Codable {
    case pending
    case success
    case error
}

/// Represents a message struct.
public struct Message: Codable, Identifiable {
    /// The id value.
    public let id: String
    /// The role value.
    public let role: MessageRole
    /// The content value.
    public let content: String
    /// The status value.
    public let status: MessageStatus
    /// The tool calls value.
    public let toolCalls: [ToolCall]?
    /// The needs newline value.
    public let needsNewline: Bool?
    /// The timestamp value.
    public let timestamp: String
    /// The error value.
    public let error: String?
    /// Raw diagnostic details for assistant-only context and on-demand UI display.
    public let errorDetails: String?

    public init(
        id: String,
        role: MessageRole,
        content: String,
        status: MessageStatus,
        toolCalls: [ToolCall]?,
        needsNewline: Bool?,
        timestamp: String,
        error: String?,
        errorDetails: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.status = status
        self.toolCalls = toolCalls
        self.needsNewline = needsNewline
        self.timestamp = timestamp
        self.error = error
        self.errorDetails = errorDetails
    }

    public init(
        id: String,
        role: MessageRole,
        content: String,
        status: MessageStatus,
        toolCalls: [ToolCall]?,
        needsNewline: Bool?,
        timestamp: String,
        error: String?
    ) {
        self.init(
            id: id,
            role: role,
            content: content,
            status: status,
            toolCalls: toolCalls,
            needsNewline: needsNewline,
            timestamp: timestamp,
            error: error,
            errorDetails: nil
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case status
        case toolCalls
        case needsNewline
        case timestamp
        case error
        case errorDetails
        case legacyErrorDetails = "error_details"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        role = (try? container.decode(MessageRole.self, forKey: .role)) ?? .assistant
        if let stringContent = try? container.decode(String.self, forKey: .content) {
            content = stringContent
        } else if let structuredContent = try? container.decode(AnyCodable.self, forKey: .content) {
            content = Message.decodeStructuredContent(structuredContent.value)
        } else {
            content = ""
        }
        status = (try? container.decode(MessageStatus.self, forKey: .status)) ?? .complete
        toolCalls = try? container.decode([ToolCall].self, forKey: .toolCalls)
        needsNewline = try? container.decodeIfPresent(Bool.self, forKey: .needsNewline)
        timestamp = (try? container.decode(String.self, forKey: .timestamp)) ?? ""
        error = try? container.decodeIfPresent(String.self, forKey: .error)
        errorDetails = try? container.decodeIfPresent(String.self, forKey: .errorDetails)
            ?? container.decodeIfPresent(String.self, forKey: .legacyErrorDetails)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
        try container.encodeIfPresent(needsNewline, forKey: .needsNewline)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(error, forKey: .error)
        try container.encodeIfPresent(errorDetails, forKey: .errorDetails)
    }

    nonisolated private static func decodeStructuredContent(_ rawValue: Any) -> String {
        switch rawValue {
        case let stringValue as String:
            return stringValue
        case let arrayValue as [Any]:
            return arrayValue
                .map(decodeStructuredContent)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n\n")
        case let dictValue as [String: Any]:
            if let textValue = dictValue["text"] as? String {
                return textValue
            }
            let preferredKeys = ["content", "parts", "children", "value"]
            for key in preferredKeys {
                if let nestedValue = dictValue[key] {
                    let decodedValue = decodeStructuredContent(nestedValue)
                    if !decodedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return decodedValue
                    }
                }
            }
            return ""
        default:
            return ""
        }
    }
}

/// Represents a conversation struct.
public struct Conversation: Codable, Identifiable {
    /// The id value.
    public let id: String
    /// The title value.
    public let title: String
    /// The title generated value.
    public let titleGenerated: Bool
    /// The created at value.
    public let createdAt: String
    /// The updated at value.
    public let updatedAt: String
    /// The message count value.
    public let messageCount: Int
    /// The first message value.
    public let firstMessage: String?
    /// Indicates whether archived.
    public let isArchived: Bool?
}

/// Represents a conversation with messages struct.
public struct ConversationWithMessages: Codable {
    /// The id value.
    public let id: String
    /// The title value.
    public let title: String
    /// The title generated value.
    public let titleGenerated: Bool
    /// The created at value.
    public let createdAt: String
    /// The updated at value.
    public let updatedAt: String
    /// The message count value.
    public let messageCount: Int
    /// The first message value.
    public let firstMessage: String?
    /// Indicates whether archived.
    public let isArchived: Bool?
    /// The messages value.
    public let messages: [Message]
}

/// Controls whether a streamed user instruction should appear in chat history.
public enum ChatStreamMessageVisibility: String, Codable {
    case visible
    case hidden
}

/// Represents a chat stream request struct.
public struct ChatStreamRequest: Codable {
    /// The message value.
    public let message: String
    /// The conversation id value.
    public let conversationId: String?
    /// The user message id value.
    public let userMessageId: String?
    /// The assistant message id value.
    public let assistantMessageId: String?
    /// The visibility of the submitted user message.
    public let messageVisibility: ChatStreamMessageVisibility?
    /// The open context value.
    public let openContext: [String: AnyCodable]?
    /// The attachments value.
    public let attachments: [ChatAttachment]?
    /// The current location value.
    public let currentLocation: String?
    /// The current location levels value.
    public let currentLocationLevels: [String: String]?
    /// The current weather value.
    public let currentWeather: [String: AnyCodable]?
    /// The current timezone value.
    public let currentTimezone: String?

    public init(
        message: String,
        conversationId: String? = nil,
        userMessageId: String? = nil,
        assistantMessageId: String? = nil,
        messageVisibility: ChatStreamMessageVisibility? = nil,
        openContext: [String: AnyCodable]? = nil,
        attachments: [ChatAttachment]? = nil,
        currentLocation: String? = nil,
        currentLocationLevels: [String: String]? = nil,
        currentWeather: [String: AnyCodable]? = nil,
        currentTimezone: String? = nil
    ) {
        self.message = message
        self.conversationId = conversationId
        self.userMessageId = userMessageId
        self.assistantMessageId = assistantMessageId
        self.messageVisibility = messageVisibility
        self.openContext = openContext
        self.attachments = attachments
        self.currentLocation = currentLocation
        self.currentLocationLevels = currentLocationLevels
        self.currentWeather = currentWeather
        self.currentTimezone = currentTimezone
    }
}

/// Represents a chat attachment struct.
public struct ChatAttachment: Codable {
    /// The file id value.
    public let fileId: String
    /// The filename value.
    public let filename: String?

    public init(fileId: String, filename: String? = nil) {
        self.fileId = fileId
        self.filename = filename
    }
}
