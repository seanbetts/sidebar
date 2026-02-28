import Foundation

public enum ExtensionURLMessageHandler {
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
        // Keep extension writes lightweight and deterministic:
        // queue first, then let the main app submit/process when active.
        _ = saveWebsite
        _ = refreshAccessToken
        return queuedWebsiteResponse(for: normalized, pendingStore: pendingStore)
    }
}
