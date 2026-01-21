import Foundation

/// Defines the requirements for ConversationsProviding.
public protocol ConversationsProviding {
    func list() async throws -> [Conversation]
    func get(id: String) async throws -> ConversationWithMessages
    func search(query: String, limit: Int) async throws -> [Conversation]
    func delete(conversationId: String) async throws -> Conversation
}

/// Defines the requirements for ConversationsAPIProviding.
public protocol ConversationsAPIProviding {
    func list() async throws -> [Conversation]
    func get(id: String) async throws -> ConversationWithMessages
    func search(query: String, limit: Int) async throws -> [Conversation]
    func delete(conversationId: String) async throws -> Conversation
    func create(title: String) async throws -> Conversation
    func addMessage(conversationId: String, message: ConversationMessageCreate) async throws -> Conversation
    func update(conversationId: String, updates: ConversationUpdateRequest) async throws -> Conversation
}

/// API client for conversation endpoints.
public struct ConversationsAPI {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func create(title: String = "New Chat") async throws -> Conversation {
        try await client.request("conversations", method: "POST", body: ConversationCreateRequest(title: title))
    }

    public func list() async throws -> [Conversation] {
        try await client.request("conversations")
    }

    public func get(id: String) async throws -> ConversationWithMessages {
        try await client.request("conversations/\(id)")
    }

    public func addMessage(conversationId: String, message: ConversationMessageCreate) async throws -> Conversation {
        try await client.request("conversations/\(conversationId)/messages", method: "POST", body: message)
    }

    public func update(conversationId: String, updates: ConversationUpdateRequest) async throws -> Conversation {
        try await client.request("conversations/\(conversationId)", method: "PUT", body: updates)
    }

    public func delete(conversationId: String) async throws -> Conversation {
        try await client.request("conversations/\(conversationId)", method: "DELETE")
    }

    public func search(query: String, limit: Int = 10) async throws -> [Conversation] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let path = "conversations/search?query=\(encoded)&limit=\(limit)"
        return try await client.request(path, method: "POST")
    }
}

extension ConversationsAPI: ConversationsProviding {}
extension ConversationsAPI: ConversationsAPIProviding {}

/// Request body for creating a conversation.
public struct ConversationCreateRequest: Codable {
    public let title: String
}

/// Request body for updating conversation metadata.
public struct ConversationUpdateRequest: Codable {
    public let title: String?
    public let titleGenerated: Bool?
    public let isArchived: Bool?
}

/// Request body for adding a conversation message.
public struct ConversationMessageCreate: Codable {
    public let id: String
    public let role: String
    public let content: String
    public let status: String?
    public let timestamp: String
    public let toolCalls: [AnyCodable]?
    public let error: String?

    public init(
        id: String,
        role: String,
        content: String,
        status: String? = nil,
        timestamp: String,
        toolCalls: [AnyCodable]? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.status = status
        self.timestamp = timestamp
        self.toolCalls = toolCalls
        self.error = error
    }
}
