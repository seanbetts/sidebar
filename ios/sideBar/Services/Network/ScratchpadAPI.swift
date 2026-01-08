import Foundation

public struct ScratchpadAPI {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func get() async throws -> ScratchpadResponse {
        try await client.request("scratchpad")
    }

    public func update(content: String, mode: ScratchpadMode? = nil) async throws -> ScratchpadResponse {
        let payload = ScratchpadUpdateRequest(content: content, mode: mode)
        struct ScratchpadUpdateResponse: Codable {
            let success: Bool
            let id: String
        }
        let _: ScratchpadUpdateResponse = try await client.request("scratchpad", method: "POST", body: payload)
        return try await get()
    }

    public func clear() async throws {
        try await client.requestVoid("scratchpad", method: "DELETE")
    }
}
