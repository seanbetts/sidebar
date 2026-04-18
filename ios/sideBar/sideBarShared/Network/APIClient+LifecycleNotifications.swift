import Foundation

public extension Notification.Name {
    static let apiClientRequestFailed = Notification.Name("sideBar.apiClient.requestFailed")
    static let apiClientRequestSucceeded = Notification.Name("sideBar.apiClient.requestSucceeded")
}

private enum APIClientNotificationUserInfoKey {
    static let error = "error"
    static let signal = "signal"
    static let statusCode = "statusCode"
}

extension APIClient {
    public func postSuccessNotification(intent: RequestIntent, statusCode: Int) {
        let signal = RequestLifecycleSignal(
            operation: intent.operation,
            requestKind: intent.requestKind,
            stage: .succeeded,
            metadata: [APIClientNotificationUserInfoKey.statusCode: String(statusCode)]
        )
        NotificationCenter.default.post(
            name: .apiClientRequestSucceeded,
            object: nil,
            userInfo: [APIClientNotificationUserInfoKey.signal: signal]
        )
    }

    public func postFailureNotification(
        intent: RequestIntent,
        statusCode: Int? = nil,
        backendMessage: String? = nil,
        transportError: Error? = nil
    ) {
        let appError = AppError.classify(
            operation: intent.operation,
            requestKind: intent.requestKind,
            responseStatus: statusCode,
            backendMessage: backendMessage,
            transportError: transportError
        )
        var metadata = appError.diagnostics
        if let statusCode {
            metadata[APIClientNotificationUserInfoKey.statusCode] = String(statusCode)
        }
        let signal = RequestLifecycleSignal(
            operation: intent.operation,
            requestKind: intent.requestKind,
            stage: .failed,
            errorCategory: appError.category,
            metadata: metadata
        )

        var userInfo: [String: Any] = [APIClientNotificationUserInfoKey.signal: signal]
        if let statusCode {
            userInfo[APIClientNotificationUserInfoKey.statusCode] = statusCode
        }
        if let transportError {
            userInfo[APIClientNotificationUserInfoKey.error] = transportError
        }

        NotificationCenter.default.post(
            name: .apiClientRequestFailed,
            object: nil,
            userInfo: userInfo
        )
    }
}
