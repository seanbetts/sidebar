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

    public init(
        success: Bool,
        toolResult: ChatToolActionResponseEvent? = nil,
        events: [ChatToolActionResponseEvent] = []
    ) {
        self.success = success
        self.toolResult = toolResult
        self.events = events
    }

    private enum CodingKeys: String, CodingKey {
        case success
        case toolResult
        case events
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        toolResult = try container.decodeIfPresent(
            ChatToolActionResponseEvent.self,
            forKey: .toolResult
        )
        events = try container.decodeIfPresent(
            [ChatToolActionResponseEvent].self,
            forKey: .events
        ) ?? []
        success = try container.decodeIfPresent(Bool.self, forKey: .success)
            ?? (toolResult?.status == ToolStatus.success.rawValue)
    }
}

/// Stream-compatible event returned from a confirmation action response.
public struct ChatToolActionResponseEvent: Decodable {
    public let type: String
    public let data: AnyCodable?

    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            self.stringValue = "\(intValue)"
            self.intValue = intValue
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case data
    }

    var status: String? {
        guard let payload = data?.value as? [String: Any] else {
            return nil
        }
        return payload["status"] as? String
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        if let explicitData = try container.decodeIfPresent(AnyCodable.self, forKey: .data) {
            data = explicitData
            return
        }

        let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
        var eventPayload: [String: Any] = [:]
        for key in dynamicContainer.allKeys where key.stringValue != CodingKeys.type.rawValue {
            if let value = try dynamicContainer.decodeIfPresent(AnyCodable.self, forKey: key) {
                eventPayload[key.stringValue] = value.value
            }
        }
        data = AnyCodable(eventPayload)
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

    public init(success: Bool, data: AnyCodable?) {
        self.success = success
        self.data = data
    }
}
