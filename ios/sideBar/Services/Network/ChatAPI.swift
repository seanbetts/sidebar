import Foundation

public struct ChatAPI {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func generateTitle(conversationId: String) async throws -> ChatTitleResponse {
        try await client.request("chat/generate-title", method: "POST", body: ChatTitleRequest(conversationId: conversationId))
    }
}

public struct ChatTitleRequest: Codable {
    public let conversationId: String
}

public struct ChatTitleResponse: Codable {
    public let title: String
    public let fallback: Bool
}
