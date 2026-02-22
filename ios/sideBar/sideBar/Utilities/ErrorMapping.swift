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
            return "Secure connection to server failed. The server certificate may have changed."
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
}
