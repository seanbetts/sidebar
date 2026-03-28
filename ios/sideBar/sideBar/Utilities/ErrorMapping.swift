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
    public let title: String
    public let pillText: String
    public let userMessage: String
    public let details: String?
    public let requestID: String?
}

public enum ErrorMapping {
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

    private static func mapAPIError(_ apiError: APIClientError) -> String {
        switch apiError {
        case .apiError(let message):
            if isAuthenticationErrorMessage(message) {
                return "Session expired. Please sign in again."
            }
            if isPromptTooLargeMessage(message) {
                return "Attachment and context are too large for one message. Remove some attachments or close open items and try again."
            }
            return message
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

    private static func messageForStatus(_ status: Int) -> String {
        switch status {
        case 408, 504:
            return "Network connection failed. Please check your internet."
        case 400:
            return "Request was rejected by the server. If this includes attachments, remove one and try again."
        case 401:
            return "Session expired. Please sign in again."
        case 403:
            return "You do not have permission to perform this action."
        case 413:
            return "File too large. Max size is 100MB."
        case 500...:
            return "Server error. Please try again soon."
        default:
            return "Request failed (HTTP \(status))."
        }
    }

    private static func messageForURLRequestErrorCategory(_ category: URLRequestErrorCategory) -> String {
        switch category {
        case .offline:
            return "Network connection failed. Please check your internet."
        case .timeout:
            return "Server took too long to respond. Please try again."
        case .serverUnreachable:
            return "Could not reach the server. Please try again."
        case .secureConnection:
            return "Unable to verify a secure connection to the server. Please try again shortly. [SEC-CONN]"
        case .authRequired:
            return "Session expired. Please sign in again."
        case .cancelled:
            return "Request was interrupted. Please try again."
        case .other:
            return "Network request failed. Please try again."
        }
    }

    private static func isAuthenticationErrorMessage(_ message: String) -> Bool {
        let lowered = message.lowercased()
        let signals = [
            "unauthorized",
            "forbidden",
            "not authenticated",
            "invalid token",
            "token expired",
            "session expired"
        ]
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

    public static func chatStreamPresentation(
        from rawError: String?,
        fallbackUserMessage: String? = nil
    ) -> ChatStreamErrorPresentation {
        let trimmedRaw = rawError?.trimmedOrNil
        let details = trimmedRaw
        let sourceText = (trimmedRaw ?? fallbackUserMessage ?? "").lowercased()
        let requestID = extractRequestID(from: trimmedRaw)

        if sourceText.contains("overloaded_error") || sourceText.contains("overloaded") {
            return ChatStreamErrorPresentation(
                title: "Provider busy",
                pillText: "Provider busy",
                userMessage: "The AI provider is busy right now. Please try again in a moment.",
                details: details,
                requestID: requestID
            )
        }

        if sourceText.contains("rate_limit")
            || sourceText.contains("rate limited")
            || sourceText.contains("too many requests") {
            return ChatStreamErrorPresentation(
                title: "Rate limited",
                pillText: "Rate limited",
                userMessage: "The AI provider is rate limited right now. Please wait a moment and try again.",
                details: details,
                requestID: requestID
            )
        }

        if sourceText.contains("no text and no tool calls")
            || sourceText.contains("empty response") {
            return ChatStreamErrorPresentation(
                title: "Empty response",
                pillText: "Empty response",
                userMessage: "The AI provider returned an empty response. Please try again.",
                details: details,
                requestID: requestID
            )
        }

        if sourceText.contains("maximum tool rounds reached") {
            return ChatStreamErrorPresentation(
                title: "Too many tool steps",
                pillText: "Too many tool steps",
                userMessage: "I couldn't finish this response because it needed too many tool steps. Try a narrower follow-up.",
                details: details,
                requestID: requestID
            )
        }

        if let fallbackUserMessage = fallbackUserMessage?.trimmedOrNil {
            return ChatStreamErrorPresentation(
                title: fallbackTitle(for: fallbackUserMessage),
                pillText: fallbackTitle(for: fallbackUserMessage),
                userMessage: fallbackUserMessage,
                details: details,
                requestID: requestID
            )
        }

        let genericMessage = "The response hit an error. Please try again."
        return ChatStreamErrorPresentation(
            title: "Response error",
            pillText: "Response error",
            userMessage: genericMessage,
            details: details,
            requestID: requestID
        )
    }

    private static func extractRequestID(from rawError: String?) -> String? {
        guard let rawError = rawError?.trimmedOrNil else {
            return nil
        }
        let patterns = [
            "request_id['\\\"]?\\s*[:=]\\s*['\\\"]([^'\\\"]+)['\\\"]",
            "requestId['\\\"]?\\s*[:=]\\s*['\\\"]([^'\\\"]+)['\\\"]"
        ]
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
        if lowered.contains("unexpectedly") || lowered.contains("interrupted") {
            return "Response interrupted"
        }
        if lowered.contains("empty response") {
            return "Empty response"
        }
        return "Response error"
    }
}
