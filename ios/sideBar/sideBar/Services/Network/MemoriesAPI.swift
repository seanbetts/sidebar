import Foundation

public struct MemoriesAPI {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func list() async throws -> [MemoryItem] {
        try await client.request("memories")
    }

    public func get(id: String) async throws -> MemoryItem {
        try await client.request("memories/\(id)")
    }

    public func create(payload: MemoryCreate) async throws -> MemoryItem {
        try await client.request("memories", method: "POST", body: payload)
    }

    public func update(id: String, payload: MemoryUpdate) async throws -> MemoryItem {
        try await client.request("memories/\(id)", method: "PATCH", body: payload)
    }

    public func delete(id: String) async throws {
        try await client.requestVoid("memories/\(id)", method: "DELETE")
    }
}
