import Foundation
import sideBarShared

/// Defines the requirements for IngestionProviding.
public protocol IngestionProviding {
    func list() async throws -> IngestionListResponse
    func getMeta(fileId: String) async throws -> IngestionMetaResponse
    func getContent(fileId: String, kind: String, range: String?) async throws -> Data
    func pin(fileId: String, pinned: Bool, clientUpdatedAt: String?) async throws
    func delete(fileId: String, clientUpdatedAt: String?) async throws
    func rename(fileId: String, filename: String, clientUpdatedAt: String?) async throws
    func ingestYouTube(url: String) async throws -> String
    func sync(_ payload: IngestionSyncRequest) async throws -> IngestionSyncResponse
}

public extension IngestionProviding {
    func pin(fileId: String, pinned: Bool) async throws {
        try await pin(fileId: fileId, pinned: pinned, clientUpdatedAt: nil)
    }

    func rename(fileId: String, filename: String) async throws {
        try await rename(fileId: fileId, filename: filename, clientUpdatedAt: nil)
    }

    func delete(fileId: String) async throws {
        try await delete(fileId: fileId, clientUpdatedAt: nil)
    }
}

/// Encodes an individual file operation for sync.
public struct IngestionOperationPayload: Codable, Equatable {
    public let operationId: String
    public let op: String
    public let id: String
    public let filename: String?
    public let pinned: Bool?
    public let clientUpdatedAt: String?

    public init(
        operationId: String,
        op: String,
        id: String,
        filename: String? = nil,
        pinned: Bool? = nil,
        clientUpdatedAt: String? = nil
    ) {
        self.operationId = operationId
        self.op = op
        self.id = id
        self.filename = filename
        self.pinned = pinned
        self.clientUpdatedAt = clientUpdatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case operationId = "operation_id"
        case op
        case id
        case filename
        case pinned
        case clientUpdatedAt = "client_updated_at"
    }
}

/// Encodes a file sync request payload.
public struct IngestionSyncRequest: Encodable {
    public let lastSync: String?
    public let operations: [IngestionOperationPayload]

    public init(lastSync: String?, operations: [IngestionOperationPayload]) {
        self.lastSync = lastSync
        self.operations = operations
    }

    private enum CodingKeys: String, CodingKey {
        case lastSync = "last_sync"
        case operations
    }
}

private struct IngestionPinRequest: Codable {
    let pinned: Bool
    let clientUpdatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case pinned
        case clientUpdatedAt = "client_updated_at"
    }
}

private struct IngestionPinnedOrderRequest: Codable {
    let order: [String]
}

private struct IngestionRenameRequest: Codable {
    let filename: String
    let clientUpdatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case filename
        case clientUpdatedAt = "client_updated_at"
    }
}

private struct IngestionDeleteRequest: Codable {
    let clientUpdatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case clientUpdatedAt = "client_updated_at"
    }
}

/// API client for ingestion endpoints.
public struct IngestionAPI {
    private let client: APIClient
    private let session: URLSession

    public init(client: APIClient, session: URLSession = .shared) {
        self.client = client
        self.session = session
    }

    public func list() async throws -> IngestionListResponse {
        try await client.request("files")
    }

    public func getMeta(fileId: String) async throws -> IngestionMetaResponse {
        try await client.request("files/\(fileId)/meta")
    }

    public func getContent(fileId: String, kind: String, range: String? = nil) async throws -> Data {
        let encodedKind = kind.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? kind
        let requestPath = "files/\(fileId)/content?kind=\(encodedKind)"
        var headers: [String: String] = [:]
        if let range {
            headers["Range"] = range
        }
        return try await client.requestData(requestPath, headers: headers)
    }

    public func pin(fileId: String, pinned: Bool) async throws {
        try await pin(fileId: fileId, pinned: pinned, clientUpdatedAt: nil)
    }

    public func pin(fileId: String, pinned: Bool, clientUpdatedAt: String? = nil) async throws {
        try await client.requestVoid(
            "files/\(fileId)/pin",
            method: "PATCH",
            body: IngestionPinRequest(pinned: pinned, clientUpdatedAt: clientUpdatedAt)
        )
    }

    public func updatePinnedOrder(ids: [String]) async throws {
        try await client.requestVoid(
            "files/pinned-order",
            method: "PATCH",
            body: IngestionPinnedOrderRequest(order: ids)
        )
    }

    public func rename(fileId: String, filename: String) async throws {
        try await rename(fileId: fileId, filename: filename, clientUpdatedAt: nil)
    }

    public func rename(
        fileId: String,
        filename: String,
        clientUpdatedAt: String? = nil
    ) async throws {
        try await client.requestVoid(
            "files/\(fileId)/rename",
            method: "PATCH",
            body: IngestionRenameRequest(filename: filename, clientUpdatedAt: clientUpdatedAt)
        )
    }

    public func pause(fileId: String) async throws {
        try await client.requestVoid("files/\(fileId)/pause", method: "POST")
    }

    public func resume(fileId: String) async throws {
        try await client.requestVoid("files/\(fileId)/resume", method: "POST")
    }

    public func cancel(fileId: String) async throws {
        try await client.requestVoid("files/\(fileId)/cancel", method: "POST")
    }

    public func delete(fileId: String) async throws {
        try await delete(fileId: fileId, clientUpdatedAt: nil)
    }

    public func delete(fileId: String, clientUpdatedAt: String? = nil) async throws {
        let body = clientUpdatedAt == nil ? nil : IngestionDeleteRequest(clientUpdatedAt: clientUpdatedAt)
        try await client.requestVoid("files/\(fileId)", method: "DELETE", body: body)
    }

    public func upload(fileData: Data, filename: String, mimeType: String, folder: String = "") async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: client.config.baseUrl.appendingPathComponent("files"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = client.config.accessTokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"folder\"\r\n\r\n".utf8))
        body.append(Data("\(folder)\r\n".utf8))
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(fileData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.unknown
        }
        guard (200...299).contains(http.statusCode) else {
            let errorDecoder = JSONDecoder()
            errorDecoder.keyDecodingStrategy = .convertFromSnakeCase
            let message = APIClient.decodeErrorMessage(data: data, decoder: errorDecoder)
            if let message {
                throw APIClientError.apiError(message)
            }
            throw APIClientError.requestFailed(http.statusCode)
        }
        struct UploadResponse: Codable { let fileId: String }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let responsePayload = try decoder.decode(UploadResponse.self, from: data)
        return responsePayload.fileId
    }

    public func ingestYouTube(url: String) async throws -> String {
        struct YouTubeRequest: Codable { let url: String }
        struct YouTubeResponse: Codable { let fileId: String }
        let response: YouTubeResponse = try await client.request("files/youtube", method: "POST", body: YouTubeRequest(url: url))
        return response.fileId
    }

    public func sync(_ payload: IngestionSyncRequest) async throws -> IngestionSyncResponse {
        try await client.request("files/sync", method: "POST", body: payload)
    }
}

extension IngestionAPI: IngestionProviding {}
