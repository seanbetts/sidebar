import Foundation

public enum ExtensionURLMessageHandler {
    enum SaveError: Error {
        case invalidBaseUrl
    }

    private struct WebsiteQuickSaveRequest: Encodable {
        let url: String
        let title: String?
    }

    private static func normalizeHost(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func isYouTubeHost(_ host: String) -> Bool {
        host == "youtube.com" ||
            host.hasSuffix(".youtube.com") ||
            host == "youtu.be" ||
            host.hasSuffix(".youtu.be")
    }

    private static func isLikelyYouTubeId(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6 else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func extractYouTubeVideoId(from components: URLComponents, host: String) -> String? {
        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            let candidate = components.path.split(separator: "/").first.map(String.init) ?? ""
            return isLikelyYouTubeId(candidate) ? candidate : nil
        }

        if let item = components.queryItems?.first(where: { $0.name == "v" }),
           let value = item.value,
           isLikelyYouTubeId(value) {
            return value
        }

        let parts = components.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        if ["shorts", "embed", "live", "v"].contains(parts[0]), isLikelyYouTubeId(parts[1]) {
            return parts[1]
        }
        return nil
    }

    public static func normalizeQueuedURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let hasExplicitScheme = trimmed.contains("://")
        let candidate = hasExplicitScheme ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        let host = normalizeHost(components.host)
        guard !host.isEmpty else { return nil }

        if isYouTubeHost(host) {
            if let videoId = extractYouTubeVideoId(from: components, host: host) {
                return "https://www.youtube.com/watch?v=\(videoId)"
            }
            if components.path == "/watch" {
                return nil
            }
        }

        components.fragment = nil
        return components.string
    }

    private static func failureResponse(_ code: ExtensionMessageCode) -> [String: Any] {
        [
            "ok": false,
            "code": code.rawValue,
            "error": ExtensionUserMessageCatalog.message(for: code)
        ]
    }

    private static func failureResponse(code: ExtensionMessageCode, message: String) -> [String: Any] {
        [
            "ok": false,
            "code": code.rawValue,
            "error": message
        ]
    }

    private static func successResponse(_ code: ExtensionMessageCode) -> [String: Any] {
        [
            "ok": true,
            "code": code.rawValue,
            "message": ExtensionUserMessageCatalog.message(for: code)
        ]
    }

    private static func queuedWebsiteResponse(
        for normalizedURL: String,
        pendingStore: PendingShareStore
    ) -> [String: Any] {
        if pendingStore.enqueueWebsite(url: normalizedURL) != nil {
            var payload = successResponse(.savedForLater)
            payload["queued"] = "website"
            return payload
        }
        return failureResponse(.queueFailed)
    }

    private static func messageCode(forDetail detail: String?) -> ExtensionMessageCode? {
        guard let detail else { return nil }
        let lowered = detail.lowercased()

        let authSignals = [
            "unauthorized",
            "forbidden",
            "access denied",
            "not authenticated",
            "invalid token",
            "token expired",
            "jwt"
        ]
        if authSignals.contains(where: lowered.contains) {
            return .notAuthenticated
        }

        let unsupportedSignals = [
            "unsupported",
            "type identifier",
            "unavailable coercion",
            "cannot load representation"
        ]
        if unsupportedSignals.contains(where: lowered.contains) {
            return .unsupportedContent
        }

        let networkSignals = [
            "timed out",
            "timeout",
            "network",
            "connection lost",
            "cannot connect",
            "could not connect",
            "offline"
        ]
        if networkSignals.contains(where: lowered.contains) {
            return .networkError
        }

        return nil
    }

    private static func mapped(_ code: ExtensionMessageCode) -> (code: ExtensionMessageCode, message: String) {
        (code, ExtensionUserMessageCatalog.message(for: code))
    }

    private static func mapSaveError(_ error: SaveError) -> (code: ExtensionMessageCode, message: String) {
        switch error {
        case .invalidBaseUrl:
            return mapped(.invalidBaseUrl)
        }
    }

    private static func mapRequestStatusCode(_ statusCode: Int) -> (code: ExtensionMessageCode, message: String) {
        switch statusCode {
        case 401, 403:
            return mapped(.notAuthenticated)
        case 408:
            return mapped(.networkError)
        default:
            return mapped(.uploadFailed)
        }
    }

    private static func mapAPIClientError(_ error: APIClientError) -> (code: ExtensionMessageCode, message: String) {
        switch error {
        case .requestFailed(let statusCode):
            return mapRequestStatusCode(statusCode)
        case .apiError(let detail):
            if let code = messageCode(forDetail: detail) {
                return mapped(code)
            }
            return (.uploadFailed, ExtensionUserMessageCatalog.uploadFailureMessage(detail: detail))
        case .missingToken:
            return mapped(.notAuthenticated)
        case .invalidUrl, .decodingFailed, .unknown:
            return mapped(.unknownFailure)
        @unknown default:
            return mapped(.unknownFailure)
        }
    }

    private static func mapError(_ error: Error) -> (code: ExtensionMessageCode, message: String) {
        if let saveError = error as? SaveError {
            return mapSaveError(saveError)
        }

        if let apiError = error as? APIClientError {
            return mapAPIClientError(apiError)
        }

        if let networkCode = ExtensionNetworkErrorClassifier.messageCode(for: error) {
            return mapped(networkCode)
        }

        return mapped(.unknownFailure)
    }

    private static func isUnauthorized(_ error: Error) -> Bool {
        if let apiError = error as? APIClientError {
            switch apiError {
            case .requestFailed(let statusCode):
                return statusCode == 401 || statusCode == 403
            case .apiError(let detail):
                return messageCode(forDetail: detail) == .notAuthenticated
            case .missingToken:
                return true
            default:
                return false
            }
        }

        let lowered = error.localizedDescription.lowercased()
        let authSignals = [
            "unauthorized",
            "forbidden",
            "access denied",
            "not authenticated",
            "invalid token",
            "token expired",
            "jwt"
        ]
        return authSignals.contains(where: lowered.contains)
    }

    private static func normalizeConfigValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("$(") && trimmed.hasSuffix(")") {
            return nil
        }
        if trimmed.hasPrefix("${") && trimmed.hasSuffix("}") {
            return nil
        }
        return trimmed.replacingOccurrences(of: "\\/", with: "/")
    }

    private static func parseHTTPURL(from value: String) -> URL? {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              !host.isEmpty else {
            return nil
        }
        return url
    }

    private static func apiBaseURL() throws -> URL {
        if let value = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           let normalized = normalizeConfigValue(value),
           let url = parseHTTPURL(from: normalized) {
            return url
        }
        throw SaveError.invalidBaseUrl
    }

    private static func saveWebsiteNow(url: String) async throws {
        let keychain = ExtensionAuthStateStoreFactory.makeSharedStore()
        guard let token = try? keychain.loadAccessToken(), !token.isEmpty else {
            throw APIClientError.missingToken
        }

        let client = APIClient(
            config: APIClientConfig(
                baseUrl: try apiBaseURL(),
                accessTokenProvider: { (try? keychain.loadAccessToken()) ?? token }
            )
        )

        try await client.requestVoid(
            "websites/quick-save",
            method: "POST",
            body: WebsiteQuickSaveRequest(url: url, title: nil)
        )
    }

    public static func handleSaveURLMessage(
        action: String?,
        urlString: String?,
        pendingStore: PendingShareStore = .shared,
        saveWebsite: ((String) async throws -> Void)? = nil,
        refreshAccessToken: (() async -> Bool)? = nil
    ) async -> [String: Any] {
        guard action == "save_url" else {
            return failureResponse(.unsupportedAction)
        }
        guard let urlString, !urlString.isEmpty else {
            return failureResponse(.missingURL)
        }
        guard let normalized = normalizeQueuedURL(urlString) else {
            return failureResponse(.invalidURL)
        }

        let saveOperation = saveWebsite ?? saveWebsiteNow(url:)
        do {
            try await saveOperation(normalized)
            return successResponse(.websiteSaved)
        } catch {
            if isUnauthorized(error),
               let refreshAccessToken,
               await refreshAccessToken() {
                do {
                    try await saveOperation(normalized)
                    return successResponse(.websiteSaved)
                } catch {
                    if ExtensionNetworkErrorClassifier.isOfflineLike(error) || isUnauthorized(error) {
                        return queuedWebsiteResponse(for: normalized, pendingStore: pendingStore)
                    }
                    let mapped = mapError(error)
                    return failureResponse(code: mapped.code, message: mapped.message)
                }
            }

            if ExtensionNetworkErrorClassifier.isOfflineLike(error) || isUnauthorized(error) {
                return queuedWebsiteResponse(for: normalized, pendingStore: pendingStore)
            }

            let mapped = mapError(error)
            return failureResponse(code: mapped.code, message: mapped.message)
        }
    }
}
