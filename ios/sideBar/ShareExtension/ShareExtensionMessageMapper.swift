import Foundation
import sideBarShared

enum ShareExtensionMessageMapper {
    static func queueResultMessage(for item: PendingShareItem?) -> String {
        ExtensionQueueResultMapper.queueMessage(for: item)
    }

    static func queueSucceeded(for item: PendingShareItem?) -> Bool {
        ExtensionQueueResultMapper.queueSucceeded(for: item)
    }

    static func errorMessage(for error: Error) -> String {
        if let shareError = error as? ShareExtensionError {
            switch shareError {
            case .notAuthenticated:
                return ExtensionUserMessageCatalog.message(for: .notAuthenticated)
            case .invalidBaseUrl:
                return ExtensionUserMessageCatalog.message(for: .invalidBaseUrl)
            case .invalidSharePayload:
                return ExtensionUserMessageCatalog.message(for: .invalidSharePayload)
            case .unsupportedContentType:
                return ExtensionUserMessageCatalog.message(for: .unsupportedContent)
            case .uploadFailed(let detail):
                if let messageCode = messageCode(forDetail: detail) {
                    return ExtensionUserMessageCatalog.message(for: messageCode)
                }
                return ExtensionUserMessageCatalog.uploadFailureMessage(detail: detail)
            }
        }

        if let apiError = error as? APIClientError {
            return message(for: apiError)
        }

        if let code = ExtensionNetworkErrorClassifier.messageCode(for: error) {
            return ExtensionUserMessageCatalog.message(for: code)
        }

        return ExtensionUserMessageCatalog.message(for: .unknownFailure)
    }

    private static func message(for error: APIClientError) -> String {
        switch error {
        case .requestFailed(let statusCode):
            switch statusCode {
            case 401, 403:
                return ExtensionUserMessageCatalog.message(for: .notAuthenticated)
            case 408:
                return ExtensionUserMessageCatalog.message(for: .networkError)
            default:
                return ExtensionUserMessageCatalog.message(for: .uploadFailed)
            }
        case .apiError(let message):
            if let code = messageCode(forDetail: message) {
                return ExtensionUserMessageCatalog.message(for: code)
            }
            let detail = ExtensionUserMessageCatalog.sanitizedDetail(message)
            return ExtensionUserMessageCatalog.uploadFailureMessage(detail: detail)
        case .missingToken:
            return ExtensionUserMessageCatalog.message(for: .notAuthenticated)
        case .invalidUrl, .decodingFailed, .unknown:
            return ExtensionUserMessageCatalog.message(for: .unknownFailure)
        }
    }

    private static func messageCode(forDetail detail: String?) -> ExtensionMessageCode? {
        guard let detail else { return nil }
        let lowered = detail.lowercased()

        let authSignals = [
            "unauthorized",
            "forbidden",
            "access denied",
            "not authenticated",
            "invalid token",
            "token expired",
            "jwt"
        ]
        if authSignals.contains(where: lowered.contains) {
            return .notAuthenticated
        }

        let networkSignals = [
            "timed out",
            "timeout",
            "network",
            "connection lost",
            "cannot connect",
            "could not connect",
            "offline"
        ]
        if networkSignals.contains(where: lowered.contains) {
            return .networkError
        }

        return nil
    }
}
