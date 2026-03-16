import Foundation

public enum ExtensionURLMessageHandler {
    public enum SaveStrategy: Equatable {
        case immediate
        case queueOnly
    }

    private enum SaveFailureDisposition {
        case queue(ExtensionMessageCode)
        case fail(ExtensionMessageCode)
    }

    private static func isIPv4Address(_ host: String) -> Bool {
        let pattern = #"^\d{1,3}(\.\d{1,3}){3}$"#
        return host.range(of: pattern, options: .regularExpression) != nil
    }

    private static func isAlphaOnly(_ value: Substring) -> Bool {
        for char in value {
            guard char.isLetter else { return false }
        }
        return true
    }

    private static func isAlphaNumericHyphen(_ value: Substring) -> Bool {
        for char in value {
            if char.isLetter || char.isNumber || char == "-" {
                continue
            }
            return false
        }
        return true
    }

    private static func isValidTld(_ value: Substring) -> Bool {
        let count = value.count
        return count >= 2 && count <= 24 && isAlphaOnly(value)
    }

    private static func isValidLabel(_ value: Substring) -> Bool {
        if value.isEmpty { return false }
        if value.hasPrefix("-") || value.hasSuffix("-") { return false }
        return isAlphaNumericHyphen(value)
    }

    private static func isValidHost(_ host: String) -> Bool {
        if host == "localhost" { return false }
        if host.contains(":") { return false }
        if isIPv4Address(host) { return false }
        if !host.contains(".") { return false }

        let labels = host.split(separator: ".")
        guard let tld = labels.last, isValidTld(tld) else {
            return false
        }
        return labels.allSatisfy { isValidLabel($0) }
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
        if components.port != nil { return nil }
        guard isValidHost(host) else { return nil }

        if isYouTubeHost(host) {
            if let videoId = extractYouTubeVideoId(from: components, host: host) {
                return "https://www.youtube.com/watch?v=\(videoId)"
            }
            if components.path == "/watch" {
                return nil
            }
            return nil
        }

        components.host = host
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
        pendingStore: PendingShareStore,
        code: ExtensionMessageCode = .savedForLater
    ) -> [String: Any] {
        if pendingStore.enqueueWebsite(url: normalizedURL) != nil {
            var payload = successResponse(code)
            payload["queued"] = "website"
            return payload
        }
        return failureResponse(.queueFailed)
    }

    private static func isUnauthorized(_ error: Error) -> Bool {
        if let apiError = error as? APIClientError {
            switch apiError {
            case .requestFailed(401), .requestFailed(403):
                return true
            case .apiError(let message):
                let lowered = message.lowercased()
                return lowered.contains("unauthorized") || lowered.contains("forbidden")
            default:
                return false
            }
        }

        let description = error.localizedDescription.lowercased()
        return description.contains("unauthorized") || description.contains("forbidden")
    }

    private static func disposition(for error: Error) -> SaveFailureDisposition {
        if isUnauthorized(error) {
            return .queue(.savedForLaterSignInRequired)
        }
        if ExtensionNetworkErrorClassifier.isOfflineLike(error) {
            return .queue(.savedForLater)
        }
        if let apiError = error as? APIClientError {
            switch apiError {
            case .requestFailed(let statusCode):
                if statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode) {
                    return .queue(.savedForLater)
                }
            case .apiError(let message):
                let lowered = message.lowercased()
                if lowered == "unable to save website" || lowered == "failed to save website" {
                    return .queue(.savedForLater)
                }
                if lowered.contains("timeout")
                    || lowered.contains("timed out")
                    || lowered.contains("temporar")
                    || lowered.contains("try again")
                    || lowered.contains("rate limit")
                    || lowered.contains("too many request")
                    || lowered.contains("unavailable")
                    || lowered.contains("gateway")
                    || lowered.contains("server error") {
                    return .queue(.savedForLater)
                }
            default:
                break
            }
        }
        return .fail(.uploadFailed)
    }

    private static func response(
        for disposition: SaveFailureDisposition,
        normalizedURL: String,
        pendingStore: PendingShareStore
    ) -> [String: Any] {
        switch disposition {
        case .queue(let code):
            return queuedWebsiteResponse(
                for: normalizedURL,
                pendingStore: pendingStore,
                code: code
            )
        case .fail(let code):
            return failureResponse(code)
        }
    }

    private static func saveImmediately(
        normalizedURL: String,
        pendingStore: PendingShareStore,
        saveWebsite: (String) async throws -> Void,
        refreshAccessToken: (() async -> Bool)?
    ) async -> [String: Any] {
        do {
            try await saveWebsite(normalizedURL)
            return successResponse(.websiteSaved)
        } catch {
            if isUnauthorized(error),
               await (refreshAccessToken?() ?? false) {
                do {
                    try await saveWebsite(normalizedURL)
                    return successResponse(.websiteSaved)
                } catch {
                    return response(
                        for: disposition(for: error),
                        normalizedURL: normalizedURL,
                        pendingStore: pendingStore
                    )
                }
            }

            return response(
                for: disposition(for: error),
                normalizedURL: normalizedURL,
                pendingStore: pendingStore
            )
        }
    }

    public static func handleSaveURLMessage(
        action: String?,
        urlString: String?,
        pendingStore: PendingShareStore = .shared,
        saveStrategy: SaveStrategy = .immediate,
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
        if saveStrategy == .queueOnly {
            return queuedWebsiteResponse(for: normalized, pendingStore: pendingStore)
        }
        guard let saveWebsite else {
            return queuedWebsiteResponse(for: normalized, pendingStore: pendingStore)
        }
        return await saveImmediately(
            normalizedURL: normalized,
            pendingStore: pendingStore,
            saveWebsite: saveWebsite,
            refreshAccessToken: refreshAccessToken
        )
    }
}
