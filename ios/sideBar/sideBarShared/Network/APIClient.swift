import Foundation
import os

// MARK: - APIClient

public extension Notification.Name {
    static let apiClientRequestFailed = Notification.Name("sideBar.apiClient.requestFailed")
    static let apiClientRequestSucceeded = Notification.Name("sideBar.apiClient.requestSucceeded")
}

/// Configuration for APIClient base URL and auth token.
public struct APIClientConfig {
    public let baseUrl: URL
    public let accessTokenProvider: () -> String?
    /// Optional hook to refresh auth state when a request fails with 401.
    ///
    /// Should return true only if auth is now available for new requests.
    public let refreshAuthIfNeeded: (() async -> Bool)?

    public init(
        baseUrl: URL,
        accessTokenProvider: @escaping () -> String?,
        refreshAuthIfNeeded: (() async -> Bool)? = nil
    ) {
        self.baseUrl = baseUrl
        self.accessTokenProvider = accessTokenProvider
        self.refreshAuthIfNeeded = refreshAuthIfNeeded
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
    public let config: APIClientConfig
    private let session: URLSession
    private let logger = Logger(subsystem: "sideBar", category: "APIClient")
    private let authRefreshMinimumInterval: TimeInterval = 45
    private var lastAuthRefreshAttempt: Date?
    private var authRefreshTask: Task<Bool, Never>?

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
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            NotificationCenter.default.post(
                name: .apiClientRequestFailed,
                object: nil,
                userInfo: ["error": error]
            )
            throw error
        }
        let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
        guard let http = response as? HTTPURLResponse else {
            logger.error("Response failed: non-HTTP response")
            NotificationCenter.default.post(name: .apiClientRequestFailed, object: nil)
            throw APIClientError.unknown
        }
        logger.debug("Response \(http.statusCode) in \(elapsedMs)ms")
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401,
               shouldAttemptAuthRefresh(for: request),
               await attemptAuthRefreshIfNeeded() {
                var retry = request
                if let token = config.accessTokenProvider() {
                    retry.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                } else {
                    retry.setValue(nil, forHTTPHeaderField: "Authorization")
                }
                return try await performRequestWithoutAuthRetry(retry)
            }

            if let body = String(data: data, encoding: .utf8), !body.isEmpty {
                let preview = body.prefix(2000)
                logger.error("Response body: \(preview, privacy: .private)")
            }
            NotificationCenter.default.post(
                name: .apiClientRequestFailed,
                object: nil,
                userInfo: ["statusCode": http.statusCode]
            )
            let decoder = Self.makeDecoder()
            let message = Self.decodeErrorMessage(data: data, decoder: decoder)
            if let message {
                throw APIClientError.apiError(message)
            }
            throw APIClientError.requestFailed(http.statusCode)
        }
        NotificationCenter.default.post(name: .apiClientRequestSucceeded, object: nil)
        return (data, http)
    }

    private func performRequestWithoutAuthRetry(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let start = Date()
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            NotificationCenter.default.post(
                name: .apiClientRequestFailed,
                object: nil,
                userInfo: ["error": error]
            )
            throw error
        }
        let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
        guard let http = response as? HTTPURLResponse else {
            logger.error("Response failed: non-HTTP response")
            NotificationCenter.default.post(name: .apiClientRequestFailed, object: nil)
            throw APIClientError.unknown
        }
        logger.debug("Response(retry) \(http.statusCode) in \(elapsedMs)ms")
        guard (200...299).contains(http.statusCode) else {
            NotificationCenter.default.post(
                name: .apiClientRequestFailed,
                object: nil,
                userInfo: ["statusCode": http.statusCode]
            )
            let decoder = Self.makeDecoder()
            let message = Self.decodeErrorMessage(data: data, decoder: decoder)
            if let message {
                throw APIClientError.apiError(message)
            }
            throw APIClientError.requestFailed(http.statusCode)
        }
        NotificationCenter.default.post(name: .apiClientRequestSucceeded, object: nil)
        return (data, http)
    }

    private func shouldAttemptAuthRefresh(for request: URLRequest) -> Bool {
        guard config.refreshAuthIfNeeded != nil else { return false }
        guard request.httpMethod?.uppercased() == "GET" else { return false }
        return request.value(forHTTPHeaderField: "Authorization") != nil
    }

    private func attemptAuthRefreshIfNeeded() async -> Bool {
        guard let refresh = config.refreshAuthIfNeeded else { return false }

        if let authRefreshTask {
            return await authRefreshTask.value
        }

        if let lastAuthRefreshAttempt,
           Date().timeIntervalSince(lastAuthRefreshAttempt) < authRefreshMinimumInterval {
            return false
        }

        lastAuthRefreshAttempt = Date()
        let task = Task { await refresh() }
        authRefreshTask = task
        defer { authRefreshTask = nil }
        return await task.value
    }

    private func logDecodingError<T>(_ error: Error, data: Data, type: T.Type) {
        logger.error("Failed to decode \(String(describing: type), privacy: .public): \(error.localizedDescription, privacy: .public)")
        if let decodingError = error as? DecodingError {
            switch decodingError {
            case .keyNotFound(let key, let context):
                let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
                logger.error("Missing key '\(key.stringValue, privacy: .public)' at path: \(path.isEmpty ? "(root)" : path, privacy: .public)")
            case .typeMismatch(let expectedType, let context):
                let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
                logger.error("Type mismatch expected \(String(describing: expectedType), privacy: .public) at path: \(path.isEmpty ? "(root)" : path, privacy: .public)")
            case .valueNotFound(let type, let context):
                let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
                logger.error("Null value for non-optional \(String(describing: type), privacy: .public) at path: \(path.isEmpty ? "(root)" : path, privacy: .public)")
            case .dataCorrupted(let context):
                let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
                logger.error("Data corrupted at path: \(path.isEmpty ? "(root)" : path, privacy: .public) - \(context.debugDescription, privacy: .public)")
            @unknown default:
                logger.error("Unknown decoding error")
            }
        }
        if let responseBody = String(data: data.prefix(3000), encoding: .utf8), !responseBody.isEmpty {
            logger.error("Decode response body: \(responseBody, privacy: .private)")
        }
    }

    public static func decodeErrorMessage(data: Data, decoder: JSONDecoder) -> String? {
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
