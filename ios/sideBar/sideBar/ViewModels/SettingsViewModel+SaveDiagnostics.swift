import Foundation
import os
import sideBarShared

private enum SettingsSaveDiagnostics {
    private static let logger = Logger(subsystem: "sideBar", category: "SettingsViewModel")

    static func logAttempt(
        operation: String,
        changedFields: [String],
        hasLoadedSettings: Bool
    ) {
        let fieldSummary = changedFields.isEmpty ? "none" : changedFields.joined(separator: ",")
        let message =
            "Attempting settings save operation=\(operation) " +
            "fields=\(fieldSummary) hasLoadedSettings=\(hasLoadedSettings)"
        logger.notice(
            "\(message, privacy: .public)"
        )
    }

    static func mappedFailureMessage(
        for error: Error,
        operation: String,
        message: String
    ) -> String {
        let diagnosticCode = diagnosticCode(for: error)
        let diagnosticStatus = diagnosticStatus(for: error) ?? "none"
        let failureMessage =
            "Settings save failed operation=\(operation) " +
            "code=\(diagnosticCode) status=\(diagnosticStatus)"
        logger.error(
            "\(failureMessage, privacy: .public)"
        )
        return message
    }

    private static func diagnosticCode(for error: Error) -> String {
        if let apiError = error as? APIClientError {
            return diagnosticCode(for: apiError)
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return "url_error"
        }
        return "unknown_error"
    }

    private static func diagnosticCode(for apiError: APIClientError) -> String {
        switch apiError {
        case .invalidUrl:
            return "invalid_url"
        case .missingToken:
            return "missing_token"
        case .requestFailed:
            return "request_failed"
        case .apiError:
            return "api_error"
        case .appError(let appError):
            return "app_error_\(appError.category.rawValue)"
        case .decodingFailed:
            return "decoding_failed"
        case .unknown:
            return "unknown_api_error"
        }
    }

    private static func diagnosticStatus(for error: Error) -> String? {
        if let apiError = error as? APIClientError {
            return diagnosticStatus(for: apiError)
        }
        return nil
    }

    private static func diagnosticStatus(for apiError: APIClientError) -> String? {
        switch apiError {
        case .requestFailed(let status):
            return String(status)
        case .appError(let appError):
            return appError.diagnostics["statusCode"]
        case .invalidUrl, .missingToken, .apiError, .decodingFailed, .unknown:
            return nil
        }
    }
}

@MainActor
extension SettingsViewModel {
    func logSettingsSaveAttempt(operation: String, changedFields: [String]) {
        SettingsSaveDiagnostics.logAttempt(
            operation: operation,
            changedFields: changedFields,
            hasLoadedSettings: settings != nil
        )
    }

    @discardableResult
    func recordSettingsSaveFailure(_ error: Error, operation: String) -> String {
        let message = settingsErrorMessage(
            for: error,
            operation: operation,
            requestKind: .foregroundMutation
        )
        return SettingsSaveDiagnostics.mappedFailureMessage(
            for: error,
            operation: operation,
            message: message
        )
    }
}
