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
                return ExtensionUserMessageCatalog.uploadFailureMessage(detail: detail)
            }
        }

        if let code = ExtensionNetworkErrorClassifier.messageCode(for: error) {
            return ExtensionUserMessageCatalog.message(for: code)
        }

        let detail = ExtensionUserMessageCatalog.sanitizedDetail(error.localizedDescription)
        return ExtensionUserMessageCatalog.uploadFailureMessage(detail: detail)
    }
}
