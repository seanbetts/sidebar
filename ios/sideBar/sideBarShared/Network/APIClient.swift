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
    private let authRefreshCoordinator = AuthRefreshCoordinator(minimumInterval: 45)

    public init(config: APIClientConfig, session: URLSession = APIClient.makeDefaultSession()) {
        self.config = config
        self.session = session
    }
    public func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: Encodable? = nil,
        headers: [String: String] = [:],
        timeoutInterval: TimeInterval? = nil
    ) async throws -> T {
        let request = try buildRequest(
            path,
            method: method,
            body: body,
            headers: headers,
            timeoutInterval: timeoutInterval
        )
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
        headers: [String: String] = [:],
        timeoutInterval: TimeInterval? = nil
    ) async throws {
        let request = try buildRequest(
            path,
            method: method,
            body: body,
            headers: headers,
            timeoutInterval: timeoutInterval
        )
        _ = try await performRequest(request)
    }

    public func requestData(
        _ path: String,
        method: String = "GET",
        headers: [String: String] = [:],
        timeoutInterval: TimeInterval? = nil
    ) async throws -> Data {
        var requestHeaders = headers
        if requestHeaders["Accept"] == nil {
            requestHeaders["Accept"] = "*/*"
        }
        let request = try buildRequest(
            path,
            method: method,
            body: nil,
            headers: requestHeaders,
            timeoutInterval: timeoutInterval
        )
        let (data, _) = try await performRequest(request)
        return data
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
            if isCancellationError(error) {
                logCancellation(request)
                throw error
            }
            logTransportError(error, request: request)
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
               shouldAttemptAuthRefresh(for: request) {
                let method = request.httpMethod ?? "GET"
                let url = request.url?.absoluteString ?? "?"
                let hadToken = request.value(forHTTPHeaderField: "Authorization") != nil
                let retryableRequestDescription =
                    "Response 401 for \(method) \(url); hadToken=\(hadToken) retrying auth refresh"
                logger.notice(
                    "\(retryableRequestDescription, privacy: .public)"
                )
                let refreshed = await attemptAuthRefreshIfNeeded()
                let tokenChanged = shouldRetryWithUpdatedToken(for: request)
                if refreshed || tokenChanged {
                    let retryDescription =
                        "Retrying \(method) \(url) after auth refresh; refreshed=\(refreshed) tokenChanged=\(tokenChanged)"
                    logger.notice(
                        "\(retryDescription, privacy: .public)"
                    )
                    var retry = request
                    if let token = config.accessTokenProvider() {
                        retry.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    } else {
                        retry.setValue(nil, forHTTPHeaderField: "Authorization")
                    }
                    return try await performRequestWithoutAuthRetry(retry)
                } else {
                    let refreshUnavailableDescription =
                        "Auth refresh unavailable for \(method) \(url); no retry token available"
                    logger.notice(
                        "\(refreshUnavailableDescription, privacy: .public)"
                    )
                }
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
            if isCancellationError(error) {
                logCancellation(request)
                throw error
            }
            logTransportError(error, request: request)
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
        let method = request.httpMethod?.uppercased() ?? "GET"
        let retryableMethods = Set(["GET", "PUT", "PATCH", "DELETE"])
        return retryableMethods.contains(method)
    }

    private func shouldRetryWithUpdatedToken(for request: URLRequest) -> Bool {
        guard let latestToken = config.accessTokenProvider(), !latestToken.isEmpty else {
            return false
        }
        return latestToken != bearerToken(from: request)
    }

    private func bearerToken(from request: URLRequest) -> String? {
        guard let header = request.value(forHTTPHeaderField: "Authorization"),
              header.hasPrefix("Bearer ") else {
            return nil
        }
        return String(header.dropFirst("Bearer ".count))
    }

    private func attemptAuthRefreshIfNeeded() async -> Bool {
        guard let refresh = config.refreshAuthIfNeeded else { return false }
        return await authRefreshCoordinator.refreshIfNeeded(using: refresh)
    }

    private func logTransportError(_ error: Error, request: URLRequest) {
        let nsError = error as NSError
        let method = request.httpMethod ?? "?"
        let url = request.url?.absoluteString ?? "?"
        let hadToken = request.value(forHTTPHeaderField: "Authorization") != nil
        logger.error(
            "Transport error \(method, privacy: .public) \(url, privacy: .public) hadToken=\(hadToken)"
        )
        logger.error(
            "Transport error detail: domain=\(nsError.domain, privacy: .public) code=\(nsError.code)"
        )
        if nsError.userInfo[NSURLErrorFailingURLPeerTrustErrorKey] != nil {
            logger.error("Transport error has peer-trust key — likely TLS/cert-pinning cancellation")
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            logger.error(
                "Underlying error: domain=\(underlying.domain, privacy: .public) code=\(underlying.code)"
            )
        }
    }

    private func isCancellationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private func logCancellation(_ request: URLRequest) {
        let method = request.httpMethod ?? "?"
        let url = request.url?.absoluteString ?? "?"
        logger.debug("Request cancelled \(method, privacy: .public) \(url, privacy: .public)")
    }

    private func logDecodingError<T>(_ error: Error, data: Data, type: T.Type) {
        logger.error("Failed to decode \(String(describing: type), privacy: .public): \(error.localizedDescription, privacy: .public)")
        if let decodingError = error as? DecodingError {
            switch decodingError {
            case .keyNotFound(let key, let context):
                let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
                let codingPath = path.isEmpty ? "(root)" : path
                logger.error(
                    "Missing key '\(key.stringValue, privacy: .public)' at path: \(codingPath, privacy: .public)"
                )
            case .typeMismatch(let expectedType, let context):
                let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
                let codingPath = path.isEmpty ? "(root)" : path
                logger.error(
                    "Type mismatch expected \(String(describing: expectedType), privacy: .public) at path: \(codingPath, privacy: .public)"
                )
            case .valueNotFound(let type, let context):
                let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
                let codingPath = path.isEmpty ? "(root)" : path
                logger.error(
                    "Null value for non-optional \(String(describing: type), privacy: .public) at path: \(codingPath, privacy: .public)"
                )
            case .dataCorrupted(let context):
                let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
                let codingPath = path.isEmpty ? "(root)" : path
                logger.error(
                    "Data corrupted at path: \(codingPath, privacy: .public) - \(context.debugDescription, privacy: .public)"
                )
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

    static func makeEncoder() -> JSONEncoder {
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

    public static func path(_ path: String, queryItems: [URLQueryItem]) -> String {
        let validItems = queryItems.filter {
            guard let value = $0.value else {
                return false
            }
            return !value.isEmpty
        }
        guard !validItems.isEmpty else {
            return path
        }
        var components = URLComponents()
        components.queryItems = validItems
        guard let query = components.percentEncodedQuery, !query.isEmpty else {
            return path
        }
        return "\(path)?\(query)"
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
private actor AuthRefreshCoordinator {
    private let minimumInterval: TimeInterval
    private var lastAttempt: Date?
    private var refreshTask: Task<Bool, Never>?

    init(minimumInterval: TimeInterval) {
        self.minimumInterval = minimumInterval
    }

    func refreshIfNeeded(using refresh: @escaping () async -> Bool) async -> Bool {
        if let refreshTask {
            return await refreshTask.value
        }

        if let lastAttempt,
           Date().timeIntervalSince(lastAttempt) < minimumInterval {
            return false
        }

        lastAttempt = Date()
        let task = Task { await refresh() }
        refreshTask = task
        defer { refreshTask = nil }
        return await task.value
    }
}
