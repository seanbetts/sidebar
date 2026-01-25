import Foundation
import os

// MARK: - APIClient

/// Configuration for APIClient base URL and auth token.
public struct APIClientConfig {
    public let baseUrl: URL
    public let accessTokenProvider: () -> String?

    public init(baseUrl: URL, accessTokenProvider: @escaping () -> String?) {
        self.baseUrl = baseUrl
        self.accessTokenProvider = accessTokenProvider
    }
}

/// Defines APIClientError.
public enum APIClientError: Error {
    case invalidUrl
    case missingToken
    case requestFailed(Int)
    case apiError(String)
    case decodingFailed
    case unknown
}

/// HTTP client for JSON and binary API requests.
public final class APIClient {
    let config: APIClientConfig
    private let session: URLSession
    private let logger = Logger(subsystem: "sideBar", category: "APIClient")

    public init(config: APIClientConfig, session: URLSession = APIClient.makeDefaultSession()) {
        self.config = config
        self.session = session
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
            let decoder = Self.makeDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            logDecodingError(error, data: data, type: T.self)
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
            if let existingQuery = components.percentEncodedQuery, !existingQuery.isEmpty {
                components.percentEncodedQuery = "\(existingQuery)&\(queryPart)"
            } else {
                components.percentEncodedQuery = queryPart
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
            let encoder = Self.makeEncoder()
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }
        return request
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let start = Date()
        if let url = request.url {
            logger.debug("Request \(request.httpMethod ?? "GET") \(url.absoluteString, privacy: .public)")
        }
        let (data, response) = try await session.data(for: request)
        let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
        guard let http = response as? HTTPURLResponse else {
            logger.error("Response failed: non-HTTP response")
            throw APIClientError.unknown
        }
        logger.debug("Response \(http.statusCode) in \(elapsedMs)ms")
        guard (200...299).contains(http.statusCode) else {
            if let body = String(data: data, encoding: .utf8), !body.isEmpty {
                let preview = body.prefix(2000)
                logger.error("Response body: \(preview, privacy: .private)")
            }
            let decoder = Self.makeDecoder()
            let message = Self.decodeErrorMessage(data: data, decoder: decoder)
            if let message {
                throw APIClientError.apiError(message)
            }
            throw APIClientError.requestFailed(http.statusCode)
        }
        return (data, http)
    }

    private func logDecodingError<T>(_ error: Error, data: Data, type: T.Type) {
        print("[APIClient] ❌ Failed to decode \(String(describing: type))")
        print("[APIClient] Error: \(error)")
        if let decodingError = error as? DecodingError {
            switch decodingError {
            case .keyNotFound(let key, let context):
                let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
                print("[APIClient] Missing key '\(key.stringValue)' at path: \(path.isEmpty ? "(root)" : path)")
            case .typeMismatch(let expectedType, let context):
                let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
                print("[APIClient] Type mismatch - expected \(expectedType) at path: \(path.isEmpty ? "(root)" : path)")
            case .valueNotFound(let type, let context):
                let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
                print("[APIClient] Null value for non-optional \(type) at path: \(path.isEmpty ? "(root)" : path)")
            case .dataCorrupted(let context):
                let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
                print("[APIClient] Data corrupted at path: \(path.isEmpty ? "(root)" : path) - \(context.debugDescription)")
            @unknown default:
                print("[APIClient] Unknown decoding error")
            }
        }
        if let responseBody = String(data: data.prefix(3000), encoding: .utf8) {
            print("[APIClient] Response body:\n\(responseBody)")
        }
    }

    static func decodeErrorMessage(data: Data, decoder: JSONDecoder) -> String? {
        guard let payload = try? decoder.decode(APIErrorResponse.self, from: data) else {
            if let errorPayload = try? decoder.decode(APIErrorEnvelope.self, from: data) {
                return errorPayload.error.message
            }
            if let message = decodeFallbackMessage(data: data) {
                return message
            }
            return nil
        }
        if let detail = payload.detail, !detail.isEmpty {
            return detail
        }
        return nil
    }

    private static func decodeFallbackMessage(data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let dict = json as? [String: Any] else {
            return nil
        }
        if let detail = dict["detail"] as? String, !detail.isEmpty {
            return detail
        }
        if let message = dict["message"] as? String, !message.isEmpty {
            return message
        }
        if let error = dict["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return message
        }
        return nil
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        return encoder
    }

    public static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.urlCache = URLCache(
            memoryCapacity: 20 * 1024 * 1024,
            diskCapacity: 0,
            diskPath: nil
        )
        let pinnedCertificates = PinnedCertificates.loadFromMainBundle()
        if !pinnedCertificates.isEmpty, !EnvironmentConfig.isRunningTestsOrPreviews() {
            let delegate = CertificatePinningDelegate(pinnedCertificates: pinnedCertificates)
            return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        }
        return URLSession(configuration: configuration)
    }
}

/// Type-erases Encodable values so they can be encoded uniformly.
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

private struct APIErrorEnvelope: Decodable {
    let error: APIErrorMessage
}

private struct APIErrorMessage: Decodable {
    let message: String
}
