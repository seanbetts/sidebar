import Foundation

public struct ChatActiveTool: Equatable {
    public let name: String
    public let status: ToolActivityStatus
    public let startedAt: Date

    public init(name: String, status: ToolActivityStatus, startedAt: Date) {
        self.name = name
        self.status = status
        self.startedAt = startedAt
    }
}

public enum ToolActivityStatus: String {
    case running
    case success
    case error
}

public struct ChatPromptPreview: Equatable {
    public let systemPrompt: String?
    public let firstMessagePrompt: String?

    public init(systemPrompt: String?, firstMessagePrompt: String?) {
        self.systemPrompt = systemPrompt
        self.firstMessagePrompt = firstMessagePrompt
    }
}

public struct ConversationGroup: Identifiable {
    public let id: String
    public let title: String
    public let conversations: [Conversation]

    public init(id: String, title: String, conversations: [Conversation]) {
        self.id = id
        self.title = title
        self.conversations = conversations
    }
}
