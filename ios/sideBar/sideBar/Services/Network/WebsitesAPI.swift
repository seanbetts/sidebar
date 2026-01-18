import Foundation

public protocol WebsitesProviding {
    func list() async throws -> WebsitesResponse
    func get(id: String) async throws -> WebsiteDetail
    func save(url: String) async throws -> WebsiteSaveResponse
    func pin(id: String, pinned: Bool) async throws -> WebsiteItem
    func rename(id: String, title: String) async throws -> WebsiteItem
    func archive(id: String, archived: Bool) async throws -> WebsiteItem
    func delete(id: String) async throws
}

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
        struct SaveRequest: Codable { let url: String }
        return try await client.request("websites/save", method: "POST", body: SaveRequest(url: url))
    }

    public func quickSave(url: String, title: String? = nil) async throws -> WebsiteQuickSaveResponse {
        struct QuickSaveRequest: Codable { let url: String; let title: String? }
        return try await client.request("websites/quick-save", method: "POST", body: QuickSaveRequest(url: url, title: title))
    }

    public func quickSaveStatus(jobId: String) async throws -> WebsiteQuickSaveJob {
        try await client.request("websites/quick-save/\(jobId)")
    }

    public func pin(id: String, pinned: Bool) async throws -> WebsiteItem {
        struct PinRequest: Codable { let pinned: Bool }
        return try await client.request("websites/\(id)/pin", method: "PATCH", body: PinRequest(pinned: pinned))
    }

    public func archive(id: String, archived: Bool) async throws -> WebsiteItem {
        struct ArchiveRequest: Codable { let archived: Bool }
        return try await client.request("websites/\(id)/archive", method: "PATCH", body: ArchiveRequest(archived: archived))
    }

    public func rename(id: String, title: String) async throws -> WebsiteItem {
        struct RenameRequest: Codable { let title: String }
        return try await client.request("websites/\(id)/rename", method: "PATCH", body: RenameRequest(title: title))
    }

    public func updatePinnedOrder(ids: [String]) async throws {
        struct PinnedOrderRequest: Codable { let order: [String] }
        try await client.requestVoid("websites/pinned-order", method: "PATCH", body: PinnedOrderRequest(order: ids))
    }

    public func download(id: String) async throws -> Data {
        try await client.requestData("websites/\(id)/download")
    }

    public func delete(id: String) async throws {
        try await client.requestVoid("websites/\(id)", method: "DELETE")
    }
}

extension WebsitesAPI: WebsitesProviding {}
