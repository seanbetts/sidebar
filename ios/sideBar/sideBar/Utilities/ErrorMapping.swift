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
public enum ErrorMapping {
    public static func message(for error: Error) -> String {
        if let appError = error as? AppError {
            return message(for: appError)
        }
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

    static func messageForAPIErrorMessage(_ message: String) -> String {
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
    static func isAuthenticationErrorMessage(_ message: String) -> Bool {
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
        return (trimmed.hasPrefix("Expected prompt ")
            && trimmed.split(separator: " ").count >= 3)
            || trimmed == "Calibration is not awaiting name acceptance"
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
}
