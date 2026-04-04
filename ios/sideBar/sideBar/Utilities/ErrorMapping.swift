import Foundation
import sideBarShared

enum URLRequestErrorCategory {
    case offline
    case timeout
    case serverUnreachable
    case secureConnection
    case authRequired
    case cancelled
    case other
}

enum URLRequestErrorClassifier {
    static func category(for error: Error) -> URLRequestErrorCategory? {
        guard let code = urlErrorCode(from: error) else {
            return nil
        }

        if code == .cancelled, appearsToBeSecureTransportCancellation(error) {
            return .secureConnection
        }

        switch code {
        case .notConnectedToInternet, .networkConnectionLost:
            return .offline
        case .timedOut:
            return .timeout
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return .serverUnreachable
        case .secureConnectionFailed,
             .appTransportSecurityRequiresSecureConnection,
             .serverCertificateHasBadDate,
             .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .clientCertificateRejected,
             .clientCertificateRequired:
            return .secureConnection
        case .userAuthenticationRequired, .userCancelledAuthentication:
            return .authRequired
        case .cancelled:
            return .cancelled
        default:
            return .other
        }
    }

    static func urlErrorCode(from error: Error) -> URLError.Code? {
        if let urlError = error as? URLError {
            return urlError.code
        }

        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return nil
        }
        return URLError.Code(rawValue: nsError.code)
    }

    private static func appearsToBeSecureTransportCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain,
              nsError.code == URLError.cancelled.rawValue else {
            return false
        }

        if nsError.userInfo[NSURLErrorFailingURLPeerTrustErrorKey] != nil {
            return true
        }

        // Check if our pinning delegate recorded a cancellation for this host.
        let failingURL =
            (nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL)
            ?? (nsError.userInfo["NSErrorFailingURLKey"] as? URL)
        if let failingURL,
           let host = failingURL.host?.lowercased(),
           CertPinCancellationRegistry.shared.wasCancelled(host: host) {
            return true
        }

        let description = nsError.localizedDescription.lowercased()
        let signals = [
            "certificate",
            "secure connection",
            "tls",
            "ssl",
            "server trust",
            "pinning"
        ]
        return signals.contains(where: description.contains)
    }
}

public struct ChatStreamErrorPresentation: Equatable {
    public let category: ChatStreamErrorCategory
    public let isRetryable: Bool
    public let title: String
    public let pillText: String
    public let userMessage: String
    public let details: String?
    public let requestID: String?
}

public enum ChatStreamErrorCategory: Equatable {
    case providerOverloaded
    case providerRateLimited
    case requestTimeout
    case transportFailure
    case emptyResponse
    case userCancelled
    case authOrPermission
    case contextTooLarge
    case toolExhaustion
    case unknown
}

public enum ErrorMapping {
    private struct ChatStreamPresentationRule {
        let matches: Bool
        let category: ChatStreamErrorCategory
        let title: String
        let userMessage: String
    }

    public static func message(for error: Error) -> String {
        if let apiError = error as? APIClientError {
            return mapAPIError(apiError)
        }
        if let authError = error as? AuthAdapterError {
            return authError.errorDescription ?? "Authentication failed."
        }
        if let keychainError = error as? KeychainError {
            return keychainError.errorDescription ?? "Keychain error."
        }
        if let category = URLRequestErrorClassifier.category(for: error) {
            return messageForURLRequestErrorCategory(category)
        }
        if error is DecodingError {
            return "Received invalid data from server."
        }
        return error.localizedDescription
    }

    public static func message(for error: Error, during operation: String) -> String {
        "Failed to \(operation): \(message(for: error))"
    }

    static func mapAPIError(_ apiError: APIClientError) -> String {
        switch apiError {
        case .apiError(let message):
            return messageForAPIErrorMessage(message)
        case .missingToken:
            return "Authentication required. Please sign in."
        case .requestFailed(let status):
            return messageForStatus(status)
        case .decodingFailed:
            return "Unexpected response from server."
        case .invalidUrl:
            return "Invalid request URL."
        case .unknown:
            return "Unexpected error."
        @unknown default:
            return "Unexpected error."
        }
    }

    private static func messageForAPIErrorMessage(_ message: String) -> String {
        if isAuthenticationErrorMessage(message) { return "Session expired. Please sign in again." }
        if isInvalidProviderAPIKeyMessage(message) { return "That API key doesn't look valid for this provider." }
        if isDatabaseTimeoutMessage(message) { return "Server is busy right now. Please try again." }
        if isCalibrationPromptConflictMessage(message) { return "I got out of sync with your setup. Please go back and try again." }
        if isCalibrationGenerationValidationMessage(message) {
            return "I couldn't finish updating my setup just yet. Your answer is saved, please try again."
        }
        if isPromptTooLargeMessage(message) {
            return "Attachment and context are too large for one message. Remove some attachments or close open items and try again."
        }
        return message
    }

    private static func messageForStatus(_ status: Int) -> String {
        switch status {
        case 408, 504: return "Network connection failed. Please check your internet."
        case 503: return "Server is busy right now. Please try again."
        case 400: return "Request was rejected by the server. If this includes attachments, remove one and try again."
        case 401: return "Session expired. Please sign in again."
        case 403: return "You do not have permission to perform this action."
        case 413: return "File too large. Max size is 100MB."
        case 500...: return "Server error. Please try again soon."
        default: return "Request failed (HTTP \(status))."
        }
    }
    private static func messageForURLRequestErrorCategory(_ category: URLRequestErrorCategory) -> String {
        switch category {
        case .offline: return "Network connection failed. Please check your internet."
        case .timeout: return "Server took too long to respond. Please try again."
        case .serverUnreachable: return "Could not reach the server. Please try again."
        case .secureConnection:
            return "Unable to verify a secure connection to the server. Please try again shortly. [SEC-CONN]"
        case .authRequired: return "Session expired. Please sign in again."
        case .cancelled: return "Request was interrupted. Please try again."
        case .other: return "Network request failed. Please try again."
        }
    }
    private static func isAuthenticationErrorMessage(_ message: String) -> Bool {
        let lowered = message.lowercased()
        let signals = ["unauthorized", "forbidden", "not authenticated", "invalid token", "token expired", "session expired"]
        return signals.contains(where: lowered.contains)
    }
    private static func isPromptTooLargeMessage(_ message: String) -> Bool {
        let lowered = message.lowercased()
        let signals = [
            "system prompt exceeds maximum size",
            "system prompt exceeded the configured maximum size",
            "message context is too large"
        ]
        return signals.contains(where: lowered.contains)
    }
    static func isInvalidProviderAPIKeyMessage(_ message: String) -> Bool {
        message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "invalid provider api key"
    }
    private static func isDatabaseTimeoutMessage(_ message: String) -> Bool {
        message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "database request timed out"
    }

    private static func isCalibrationPromptConflictMessage(_ message: String) -> Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("Expected prompt ") && trimmed.split(separator: " ").count >= 3
    }

    private static func isCalibrationGenerationValidationMessage(_ message: String) -> Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let calibrationSignals = [
            "I couldn't finish updating my setup just yet. Your answer is saved, please try again.",
            "I couldn't choose a name just yet. Your setup is saved, please try again.",
            "Generated invalid JSON",
            "Generated invalid JSON object",
            "must be a non-empty string",
            "must differ from the previous rejected name",
            "returned unexpected top-level keys",
            "must return an object payload",
            "returned unexpected nested keys"
        ]
        return calibrationSignals.contains(where: trimmed.contains)
            || trimmed.hasPrefix("assistant_identity.")
            || trimmed.hasPrefix("assistant_soul.")
    }

    public static func chatStreamPresentation(
        from rawError: String?,
        fallbackUserMessage: String? = nil
    ) -> ChatStreamErrorPresentation {
        let trimmedRaw = rawError?.trimmedOrNil
        let details = trimmedRaw
        let sourceText = [trimmedRaw, fallbackUserMessage?.trimmedOrNil]
            .compactMap { $0?.lowercased() }
            .joined(separator: "\n")
        let requestID = extractRequestID(from: trimmedRaw)

        if let matchedPresentation = matchedChatStreamPresentation(
            sourceText: sourceText,
            details: details,
            requestID: requestID,
            fallbackUserMessage: fallbackUserMessage?.trimmedOrNil
        ) {
            return matchedPresentation
        }

        return fallbackChatStreamPresentation(
            details: details,
            requestID: requestID,
            fallbackUserMessage: fallbackUserMessage?.trimmedOrNil
        )
    }

    private static func matchedChatStreamPresentation(
        sourceText: String,
        details: String?,
        requestID: String?,
        fallbackUserMessage: String?
    ) -> ChatStreamErrorPresentation? {
        let matchedRule = retryableChatStreamRules(
            sourceText: sourceText,
            fallbackUserMessage: fallbackUserMessage
        ).first(where: \.matches)
            ?? nonRetryableChatStreamRules(
                sourceText: sourceText,
                fallbackUserMessage: fallbackUserMessage
            ).first(where: \.matches)

        guard let matchedRule else {
            return nil
        }

        return makeChatStreamPresentation(
            category: matchedRule.category,
            title: matchedRule.title,
            userMessage: matchedRule.userMessage,
            details: details,
            requestID: requestID
        )
    }

    private static func retryableChatStreamRules(
        sourceText: String,
        fallbackUserMessage: String?
    ) -> [ChatStreamPresentationRule] {
        [
            ChatStreamPresentationRule(
                matches: sourceText.contains("overloaded_error") || sourceText.contains("overloaded"),
                category: .providerOverloaded,
                title: "Provider busy",
                userMessage: "The AI provider is busy right now. Please try again in a moment."
            ),
            ChatStreamPresentationRule(
                matches: sourceText.contains("rate_limit")
                    || sourceText.contains("rate limited")
                    || sourceText.contains("too many requests"),
                category: .providerRateLimited,
                title: "Rate limited",
                userMessage: "The AI provider is rate limited right now. Please wait a moment and try again."
            ),
            ChatStreamPresentationRule(
                matches: sourceText.contains("no text and no tool calls")
                    || sourceText.contains("empty response")
                    || sourceText.contains("ended before any text was received"),
                category: .emptyResponse,
                title: "Empty response",
                userMessage: "The AI provider returned an empty response. Please try again."
            ),
            ChatStreamPresentationRule(
                matches: sourceText.contains("timed out")
                    || sourceText.contains("timeout")
                    || sourceText.contains("408")
                    || sourceText.contains("504")
                    || sourceText.contains("nsurlerrordomain error -1001")
                    || sourceText.contains("took too long to respond"),
                category: .requestTimeout,
                title: "Request timed out",
                userMessage: fallbackUserMessage ?? "The request timed out. Please try again."
            ),
            ChatStreamPresentationRule(
                matches: sourceText.contains("offline")
                    || sourceText.contains("nsurlerrordomain error -1003")
                    || sourceText.contains("nsurlerrordomain error -1004")
                    || sourceText.contains("nsurlerrordomain error -1005")
                    || sourceText.contains("nsurlerrordomain error -1009")
                    || sourceText.contains("not connected to internet")
                    || sourceText.contains("network connection")
                    || sourceText.contains("could not reach the server")
                    || sourceText.contains("cannot connect to host")
                    || sourceText.contains("cannot find host")
                    || sourceText.contains("connection lost")
                    || sourceText.contains("stream ended unexpectedly")
                    || sourceText.contains("secure connection")
                    || sourceText.contains("tls")
                    || sourceText.contains("ssl"),
                category: .transportFailure,
                title: "Network error",
                userMessage: fallbackUserMessage ?? "The network connection was interrupted. Please try again."
            )
        ]
    }

    private static func nonRetryableChatStreamRules(
        sourceText: String,
        fallbackUserMessage: String?
    ) -> [ChatStreamPresentationRule] {
        [
            ChatStreamPresentationRule(
                matches: sourceText.contains("maximum tool rounds reached"),
                category: .toolExhaustion,
                title: "Too many tool steps",
                userMessage: "I couldn't finish this response because it needed too many tool steps. Try a narrower follow-up."
            ),
            ChatStreamPresentationRule(
                matches: sourceText.contains("no api key configured for provider"),
                category: .authOrPermission,
                title: "API key required",
                userMessage: "Add an API key in Settings to start using chat."
            ),
            ChatStreamPresentationRule(
                matches: sourceText.contains("no primary ai provider configured for strict byok mode"),
                category: .authOrPermission,
                title: "AI provider required",
                userMessage: "Choose an AI provider in Settings to start using chat."
            ),
            ChatStreamPresentationRule(
                matches: sourceText.contains("authentication_error")
                    || sourceText.contains("unauthorized")
                    || sourceText.contains("forbidden")
                    || sourceText.contains("not authenticated")
                    || sourceText.contains("invalid token")
                    || sourceText.contains("permission"),
                category: .authOrPermission,
                title: "Authentication required",
                userMessage: fallbackUserMessage ?? "Authentication failed. Please sign in again."
            ),
            ChatStreamPresentationRule(
                matches: sourceText.contains("context length exceeded")
                    || sourceText.contains("maximum allowed tokens")
                    || sourceText.contains("message context is too large")
                    || sourceText.contains("prompt too large"),
                category: .contextTooLarge,
                title: "Context too large",
                userMessage: fallbackUserMessage ?? "This request is too large to retry without reducing context."
            ),
            ChatStreamPresentationRule(
                matches: sourceText.contains("cancellationerror")
                    || sourceText.contains("cancelled by user")
                    || sourceText.contains("canceled by user")
                    || sourceText.contains("request was interrupted"),
                category: .userCancelled,
                title: "Request cancelled",
                userMessage: fallbackUserMessage ?? "The request was cancelled before it completed."
            )
        ]
    }

    private static func fallbackChatStreamPresentation(
        details: String?,
        requestID: String?,
        fallbackUserMessage: String?
    ) -> ChatStreamErrorPresentation {
        if let fallbackUserMessage {
            return makeChatStreamPresentation(
                category: .unknown,
                title: fallbackTitle(for: fallbackUserMessage),
                userMessage: fallbackUserMessage,
                details: details,
                requestID: requestID
            )
        }

        return makeChatStreamPresentation(
            category: .unknown,
            title: "Response error",
            userMessage: "The response hit an error. Please try again.",
            details: details,
            requestID: requestID
        )
    }

    private static func makeChatStreamPresentation(
        category: ChatStreamErrorCategory,
        title: String,
        userMessage: String,
        details: String?,
        requestID: String?
    ) -> ChatStreamErrorPresentation {
        ChatStreamErrorPresentation(
            category: category,
            isRetryable: isRetryable(category),
            title: title,
            pillText: title,
            userMessage: userMessage,
            details: details,
            requestID: requestID
        )
    }

    private static func isRetryable(_ category: ChatStreamErrorCategory) -> Bool {
        switch category {
        case .providerOverloaded, .providerRateLimited, .requestTimeout, .transportFailure, .emptyResponse:
            return true
        case .userCancelled, .authOrPermission, .contextTooLarge, .toolExhaustion, .unknown:
            return false
        }
    }

    private static func extractRequestID(from rawError: String?) -> String? {
        guard let rawError = rawError?.trimmedOrNil else {
            return nil
        }
        let patterns = ["request_id['\\\"]?\\s*[:=]\\s*['\\\"]([^'\\\"]+)['\\\"]", "requestId['\\\"]?\\s*[:=]\\s*['\\\"]([^'\\\"]+)['\\\"]"]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let range = NSRange(rawError.startIndex..<rawError.endIndex, in: rawError)
            guard let match = regex.firstMatch(in: rawError, range: range),
                  let captureRange = Range(match.range(at: 1), in: rawError) else {
                continue
            }
            let requestID = String(rawError[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !requestID.isEmpty {
                return requestID
            }
        }
        return nil
    }

    private static func fallbackTitle(for message: String) -> String {
        let lowered = message.lowercased()
        if lowered.contains("unexpectedly") || lowered.contains("interrupted") { return "Response interrupted" }
        if lowered.contains("empty response") { return "Empty response" }
        return "Response error"
    }
}
