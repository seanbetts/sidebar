import Foundation

public enum MessageRole: String, Codable {
    case user
    case assistant
}

public enum MessageStatus: String, Codable {
    case pending
    case streaming
    case complete
    case error
}

public struct ToolCall: Codable, Identifiable {
    public let id: String
    public let name: String
    public let parameters: [String: AnyCodable]
    public let status: ToolStatus
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

public enum ToolStatus: String, Codable {
    case pending
    case success
    case error
}

public struct Message: Codable, Identifiable {
    public let id: String
    public let role: MessageRole
    public let content: String
    public let status: MessageStatus
    public let toolCalls: [ToolCall]?
    public let needsNewline: Bool?
    public let timestamp: String
    public let error: String?
}

public struct Conversation: Codable, Identifiable {
    public let id: String
    public let title: String
    public let titleGenerated: Bool
    public let createdAt: String
    public let updatedAt: String
    public let messageCount: Int
    public let firstMessage: String?
    public let isArchived: Bool?
}

public struct ConversationWithMessages: Codable {
    public let id: String
    public let title: String
    public let titleGenerated: Bool
    public let createdAt: String
    public let updatedAt: String
    public let messageCount: Int
    public let firstMessage: String?
    public let isArchived: Bool?
    public let messages: [Message]
}

public struct ChatStreamRequest: Codable {
    public let message: String
    public let conversationId: String?
    public let userMessageId: String?
    public let openContext: [String: AnyCodable]?
    public let attachments: [ChatAttachment]?
    public let currentLocation: String?
    public let currentLocationLevels: [String: String]?
    public let currentWeather: [String: AnyCodable]?
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

public struct ChatAttachment: Codable {
    public let fileId: String
    public let filename: String?

    public init(fileId: String, filename: String? = nil) {
        self.fileId = fileId
        self.filename = filename
    }
}
