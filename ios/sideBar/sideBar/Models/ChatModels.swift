import Foundation
import sideBarShared

/// Represents a message role enum.
public enum MessageRole: String, Codable {
    case user
    case assistant
}

/// Represents a message status enum.
public enum MessageStatus: String, Codable {
    case pending
    case streaming
    case complete
    case error
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

    public init(
        id: String,
        name: String,
        parameters: [String: AnyCodable],
        status: ToolStatus,
        result: AnyCodable? = nil
    ) {
        self.id = id
        self.name = name
        self.parameters = parameters
        self.status = status
        self.result = result
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

/// Represents a chat stream request struct.
public struct ChatStreamRequest: Codable {
    /// The message value.
    public let message: String
    /// The conversation id value.
    public let conversationId: String?
    /// The user message id value.
    public let userMessageId: String?
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
