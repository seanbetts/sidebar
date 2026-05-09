import Foundation
import sideBarShared

/// Defines chat-related API operations used by the chat view model.
public protocol ChatAPIProviding {
    func generateTitle(conversationId: String) async throws -> ChatTitleResponse
    func resolveToolConfirmation(
        confirmationId: String,
        decision: ChatToolActionDecision
    ) async throws -> ChatToolActionResponse
    func undoToolAction(undoToken: String) async throws -> ChatToolUndoResponse
}

/// API client for chat-related endpoints.
public struct ChatAPI {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func generateTitle(conversationId: String) async throws -> ChatTitleResponse {
        try await client.request("chat/generate-title", method: "POST", body: ChatTitleRequest(conversationId: conversationId))
    }

    public func resolveToolConfirmation(
        confirmationId: String,
        decision: ChatToolActionDecision
    ) async throws -> ChatToolActionResponse {
        try await client.request(
            "chat/tool-confirmations/\(confirmationId)",
            method: "POST",
            body: ChatToolConfirmationDecisionRequest(decision: decision)
        )
    }

    public func undoToolAction(undoToken: String) async throws -> ChatToolUndoResponse {
        try await client.request(
            "chat/undo/\(undoToken)",
            method: "POST",
            body: ChatToolUndoRequest()
        )
    }
}

extension ChatAPI: ChatAPIProviding {}

/// Request body for generating a conversation title.
public struct ChatTitleRequest: Codable {
    public let conversationId: String

    private enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
    }
}

/// Response payload for a generated conversation title.
public struct ChatTitleResponse: Codable {
    public let title: String
    public let fallback: Bool
}

/// Request payload for resolving a pending destructive tool confirmation.
public struct ChatToolConfirmationDecisionRequest: Codable {
    public let decision: ChatToolActionDecision
    public let clientRequestId: String?

    public init(decision: ChatToolActionDecision, clientRequestId: String? = nil) {
        self.decision = decision
        self.clientRequestId = clientRequestId
    }

    private enum CodingKeys: String, CodingKey {
        case decision
        case clientRequestId = "client_request_id"
    }
}

/// Request payload for consuming a short-lived undo token.
public struct ChatToolUndoRequest: Codable {
    public let clientRequestId: String?

    public init(clientRequestId: String? = nil) {
        self.clientRequestId = clientRequestId
    }

    private enum CodingKeys: String, CodingKey {
        case clientRequestId = "client_request_id"
    }
}

/// Response payload returned after resolving a destructive tool confirmation.
public struct ChatToolActionResponse: Decodable {
    public let success: Bool
    public let toolResult: ChatToolActionResponseEvent?
    public let events: [ChatToolActionResponseEvent]

    private enum CodingKeys: String, CodingKey {
        case success
        case toolResult = "tool_result"
        case events
    }
}

/// Stream-compatible event returned from a confirmation action response.
public struct ChatToolActionResponseEvent: Decodable {
    public let type: String
    public let data: AnyCodable?

    private enum CodingKeys: String, CodingKey {
        case type
        case data
    }

    public init(type: String, data: AnyCodable?) {
        self.type = type
        self.data = data
    }
}

/// Response payload returned after consuming an undo token.
public struct ChatToolUndoResponse: Decodable {
    public let success: Bool
    public let data: AnyCodable?
}
