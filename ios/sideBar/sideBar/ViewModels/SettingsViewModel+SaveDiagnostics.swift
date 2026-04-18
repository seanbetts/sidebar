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
        let failureMessage =
            "Settings save failed operation=\(operation) error=\(message)"
        logger.error(
            "\(failureMessage, privacy: .public)"
        )
        if let apiError = error as? APIClientError {
            let apiErrorMessage =
                "Settings save API error operation=\(operation) detail=\(String(describing: apiError))"
            logger.error(
                "\(apiErrorMessage, privacy: .public)"
            )
        } else {
            let nsError = error as NSError
            let underlyingMessage =
                "Settings save underlying error operation=\(operation) domain=\(nsError.domain) code=\(nsError.code)"
            logger.error(
                "\(underlyingMessage, privacy: .public)"
            )
        }
        return message
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
