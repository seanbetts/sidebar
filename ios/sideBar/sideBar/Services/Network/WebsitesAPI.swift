import Foundation
import sideBarShared

/// Defines the requirements for WebsitesProviding.
public protocol WebsitesProviding {
    func list() async throws -> WebsitesResponse
    func get(id: String) async throws -> WebsiteDetail
    func save(url: String) async throws -> WebsiteSaveResponse
    func pin(id: String, pinned: Bool, clientUpdatedAt: String?) async throws -> WebsiteItem
    func rename(id: String, title: String, clientUpdatedAt: String?) async throws -> WebsiteItem
    func archive(id: String, archived: Bool, clientUpdatedAt: String?) async throws -> WebsiteItem
    func delete(id: String, clientUpdatedAt: String?) async throws
    func sync(_ payload: WebsiteSyncRequest) async throws -> WebsiteSyncResponse
}

public extension WebsitesProviding {
    func pin(id: String, pinned: Bool) async throws -> WebsiteItem {
        try await pin(id: id, pinned: pinned, clientUpdatedAt: nil)
    }

    func rename(id: String, title: String) async throws -> WebsiteItem {
        try await rename(id: id, title: title, clientUpdatedAt: nil)
    }

    func archive(id: String, archived: Bool) async throws -> WebsiteItem {
        try await archive(id: id, archived: archived, clientUpdatedAt: nil)
    }

    func delete(id: String) async throws {
        try await delete(id: id, clientUpdatedAt: nil)
    }
}

/// Encodes an individual website operation for sync.
public struct WebsiteOperationPayload: Codable, Equatable {
    public let operationId: String
    public let op: String
    public let id: String
    public let title: String?
    public let pinned: Bool?
    public let archived: Bool?
    public let clientUpdatedAt: String?

    public init(
        operationId: String,
        op: String,
        id: String,
        title: String? = nil,
        pinned: Bool? = nil,
        archived: Bool? = nil,
        clientUpdatedAt: String? = nil
    ) {
        self.operationId = operationId
        self.op = op
        self.id = id
        self.title = title
        self.pinned = pinned
        self.archived = archived
        self.clientUpdatedAt = clientUpdatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case operationId = "operation_id"
        case op
        case id
        case title
        case pinned
        case archived
        case clientUpdatedAt = "client_updated_at"
    }
}

/// Encodes a website sync request payload.
public struct WebsiteSyncRequest: Encodable {
    public let lastSync: String?
    public let operations: [WebsiteOperationPayload]

    public init(lastSync: String?, operations: [WebsiteOperationPayload]) {
        self.lastSync = lastSync
        self.operations = operations
    }

    private enum CodingKeys: String, CodingKey {
        case lastSync = "last_sync"
        case operations
    }
}

private struct WebsiteSaveRequest: Codable {
    let url: String
}

private struct WebsiteQuickSaveRequest: Codable {
    let url: String
    let title: String?
}

private struct WebsitePinRequest: Codable {
    let pinned: Bool
    let clientUpdatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case pinned
        case clientUpdatedAt = "client_updated_at"
    }
}

private struct WebsiteArchiveRequest: Codable {
    let archived: Bool
    let clientUpdatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case archived
        case clientUpdatedAt = "client_updated_at"
    }
}

private struct WebsiteRenameRequest: Codable {
    let title: String
    let clientUpdatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case title
        case clientUpdatedAt = "client_updated_at"
    }
}

private struct WebsitePinnedOrderRequest: Codable {
    let order: [String]
}

private struct WebsiteDeleteRequest: Codable {
    let clientUpdatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case clientUpdatedAt = "client_updated_at"
    }
}

/// API client for website endpoints.
public struct WebsitesAPI {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func list() async throws -> WebsitesResponse {
        try await client.request("websites")
    }

    public func search(query: String, limit: Int = 50) async throws -> WebsitesResponse {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let path = "websites/search?query=\(encoded)&limit=\(limit)"
        return try await client.request(path, method: "POST")
    }

    public func get(id: String) async throws -> WebsiteDetail {
        try await client.request("websites/\(id)")
    }

    public func save(url: String) async throws -> WebsiteSaveResponse {
        return try await client.request("websites/save", method: "POST", body: WebsiteSaveRequest(url: url))
    }

    public func quickSave(url: String, title: String? = nil) async throws -> WebsiteQuickSaveResponse {
        return try await client.request(
            "websites/quick-save",
            method: "POST",
            body: WebsiteQuickSaveRequest(url: url, title: title)
        )
    }

    public func pin(id: String, pinned: Bool) async throws -> WebsiteItem {
        try await pin(id: id, pinned: pinned, clientUpdatedAt: nil)
    }

    public func pin(id: String, pinned: Bool, clientUpdatedAt: String? = nil) async throws -> WebsiteItem {
        return try await client.request(
            "websites/\(id)/pin",
            method: "PATCH",
            body: WebsitePinRequest(pinned: pinned, clientUpdatedAt: clientUpdatedAt)
        )
    }

    public func archive(id: String, archived: Bool) async throws -> WebsiteItem {
        try await archive(id: id, archived: archived, clientUpdatedAt: nil)
    }

    public func archive(
        id: String,
        archived: Bool,
        clientUpdatedAt: String? = nil
    ) async throws -> WebsiteItem {
        return try await client.request(
            "websites/\(id)/archive",
            method: "PATCH",
            body: WebsiteArchiveRequest(archived: archived, clientUpdatedAt: clientUpdatedAt)
        )
    }

    public func rename(id: String, title: String) async throws -> WebsiteItem {
        try await rename(id: id, title: title, clientUpdatedAt: nil)
    }

    public func rename(id: String, title: String, clientUpdatedAt: String? = nil) async throws -> WebsiteItem {
        return try await client.request(
            "websites/\(id)/rename",
            method: "PATCH",
            body: WebsiteRenameRequest(title: title, clientUpdatedAt: clientUpdatedAt)
        )
    }

    public func updatePinnedOrder(ids: [String]) async throws {
        try await client.requestVoid(
            "websites/pinned-order",
            method: "PATCH",
            body: WebsitePinnedOrderRequest(order: ids)
        )
    }

    public func download(id: String) async throws -> Data {
        try await client.requestData("websites/\(id)/download")
    }

    public func delete(id: String) async throws {
        try await delete(id: id, clientUpdatedAt: nil)
    }

    public func delete(id: String, clientUpdatedAt: String? = nil) async throws {
        let body = clientUpdatedAt == nil ? nil : WebsiteDeleteRequest(clientUpdatedAt: clientUpdatedAt)
        try await client.requestVoid("websites/\(id)", method: "DELETE", body: body)
    }

    public func sync(_ payload: WebsiteSyncRequest) async throws -> WebsiteSyncResponse {
        try await client.request("websites/sync", method: "POST", body: payload)
    }
}

extension WebsitesAPI: WebsitesProviding {}
