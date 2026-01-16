import Foundation
import os

public struct APIClientConfig {
    public let baseUrl: URL
    public let accessTokenProvider: () -> String?

    public init(baseUrl: URL, accessTokenProvider: @escaping () -> String?) {
        self.baseUrl = baseUrl
        self.accessTokenProvider = accessTokenProvider
    }
}

public enum APIClientError: Error {
    case invalidUrl
    case missingToken
    case requestFailed(Int)
    case apiError(String)
    case decodingFailed
    case unknown
}

public final class APIClient {
    let config: APIClientConfig
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let logger = Logger(subsystem: "sideBar", category: "APIClient")

    public init(config: APIClientConfig, session: URLSession = APIClient.makeDefaultSession()) {
        self.config = config
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .useDefaultKeys
    }

    public func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: Encodable? = nil,
        headers: [String: String] = [:]
    ) async throws -> T {
        let request = try buildRequest(path, method: method, body: body, headers: headers)
        let (data, _) = try await performRequest(request)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIClientError.decodingFailed
        }
    }

    public func requestVoid(
        _ path: String,
        method: String = "POST",
        body: Encodable? = nil,
        headers: [String: String] = [:]
    ) async throws {
        let request = try buildRequest(path, method: method, body: body, headers: headers)
        _ = try await performRequest(request)
    }

    public func requestData(
        _ path: String,
        method: String = "GET",
        headers: [String: String] = [:]
    ) async throws -> Data {
        var requestHeaders = headers
        if requestHeaders["Accept"] == nil {
            requestHeaders["Accept"] = "*/*"
        }
        let request = try buildRequest(path, method: method, body: nil, headers: requestHeaders)
        let (data, _) = try await performRequest(request)
        return data
    }

    private func buildRequest(
        _ path: String,
        method: String,
        body: Encodable?,
        headers: [String: String]
    ) throws -> URLRequest {
        let url: URL
        if let queryIndex = path.firstIndex(of: "?") {
            let pathPart = String(path[..<queryIndex])
            let queryPart = String(path[path.index(after: queryIndex)...])
            guard var components = URLComponents(url: config.baseUrl, resolvingAgainstBaseURL: false) else {
                throw APIClientError.invalidUrl
            }
            let trimmedPath = pathPart.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let basePath = components.path
            if basePath.isEmpty {
                components.path = "/\(trimmedPath)"
            } else if basePath.hasSuffix("/") {
                components.path = "\(basePath)\(trimmedPath)"
            } else {
                components.path = "\(basePath)/\(trimmedPath)"
            }
            if let existingQuery = components.query, !existingQuery.isEmpty {
                components.query = "\(existingQuery)&\(queryPart)"
            } else {
                components.query = queryPart
            }
            guard let composedUrl = components.url else {
                throw APIClientError.invalidUrl
            }
            url = composedUrl
        } else {
            url = config.baseUrl.appendingPathComponent(path)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = config.accessTokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let body {
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }
        return request
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let start = Date()
        if let url = request.url {
            let path = url.path + (url.query.map { "?\($0)" } ?? "")
            logger.debug("Request \(request.httpMethod ?? "GET") \(path, privacy: .public)")
        }
        let (data, response) = try await session.data(for: request)
        let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
        guard let http = response as? HTTPURLResponse else {
            logger.error("Response failed: non-HTTP response")
            throw APIClientError.unknown
        }
        logger.debug("Response \(http.statusCode) in \(elapsedMs)ms")
        guard (200...299).contains(http.statusCode) else {
            let message = Self.decodeErrorMessage(data: data, decoder: decoder)
            if let message {
                throw APIClientError.apiError(message)
            }
            throw APIClientError.requestFailed(http.statusCode)
        }
        return (data, http)
    }

    static func decodeErrorMessage(data: Data, decoder: JSONDecoder) -> String? {
        guard let payload = try? decoder.decode(APIErrorResponse.self, from: data) else {
            return nil
        }
        if let detail = payload.detail, !detail.isEmpty {
            return detail
        }
        return nil
    }

    public static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        return URLSession(configuration: configuration)
    }
}

public struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void

    public init(_ value: Encodable) {
        self.encodeFunc = value.encode
    }

    public func encode(to encoder: Encoder) throws {
        try encodeFunc(encoder)
    }
}

private struct APIErrorResponse: Decodable {
    let detail: String?
}
