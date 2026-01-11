import Foundation

public protocol IngestionProviding {
    func list() async throws -> IngestionListResponse
    func getMeta(fileId: String) async throws -> IngestionMetaResponse
    func getContent(fileId: String, kind: String, range: String?) async throws -> Data
    func pin(fileId: String, pinned: Bool) async throws
}

public struct IngestionAPI {
    private let client: APIClient
    private let session: URLSession

    public init(client: APIClient, session: URLSession = .shared) {
        self.client = client
        self.session = session
    }

    public func list() async throws -> IngestionListResponse {
        try await client.request("ingestion")
    }

    public func getMeta(fileId: String) async throws -> IngestionMetaResponse {
        try await client.request("ingestion/\(fileId)/meta")
    }

    public func getContent(fileId: String, kind: String, range: String? = nil) async throws -> Data {
        let encodedKind = kind.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? kind
        let requestPath = "ingestion/\(fileId)/content?kind=\(encodedKind)"
        var headers: [String: String] = [:]
        if let range {
            headers["Range"] = range
        }
        return try await client.requestData(requestPath, headers: headers)
    }

    public func pin(fileId: String, pinned: Bool) async throws {
        struct PinRequest: Codable { let pinned: Bool }
        try await client.requestVoid("ingestion/\(fileId)/pin", method: "PATCH", body: PinRequest(pinned: pinned))
    }

    public func updatePinnedOrder(ids: [String]) async throws {
        struct PinnedOrderRequest: Codable { let order: [String] }
        try await client.requestVoid("ingestion/pinned-order", method: "PATCH", body: PinnedOrderRequest(order: ids))
    }

    public func rename(fileId: String, filename: String) async throws {
        struct RenameRequest: Codable { let filename: String }
        try await client.requestVoid("ingestion/\(fileId)/rename", method: "PATCH", body: RenameRequest(filename: filename))
    }

    public func pause(fileId: String) async throws {
        try await client.requestVoid("ingestion/\(fileId)/pause", method: "POST")
    }

    public func resume(fileId: String) async throws {
        try await client.requestVoid("ingestion/\(fileId)/resume", method: "POST")
    }

    public func cancel(fileId: String) async throws {
        try await client.requestVoid("ingestion/\(fileId)/cancel", method: "POST")
    }

    public func delete(fileId: String) async throws {
        try await client.requestVoid("ingestion/\(fileId)", method: "DELETE")
    }

    public func upload(fileData: Data, filename: String, mimeType: String, folder: String = "") async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: client.config.baseUrl.appendingPathComponent("ingestion"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = client.config.accessTokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"folder\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(folder)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
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
}

extension IngestionAPI: IngestionProviding {}
