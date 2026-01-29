import Foundation
import sideBarShared

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
        if error is URLError {
            return "Network connection failed. Please check your internet."
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
            return message
        case .missingToken:
            return "Authentication required. Please sign in."
        case .requestFailed(let status):
            if status == 401 {
                return "Session expired. Please sign in again."
            }
            if status == 403 {
                return "You do not have permission to perform this action."
            }
            if status == 413 {
                return "File too large. Max size is 100MB."
            }
            if status >= 500 {
                return "Server error. Please try again soon."
            }
            return "Request failed (HTTP \(status))."
        case .decodingFailed:
            return "Unexpected response from server."
        case .invalidUrl:
            return "Invalid request URL."
        case .unknown:
            return "Unexpected error."
        }
    }
}
