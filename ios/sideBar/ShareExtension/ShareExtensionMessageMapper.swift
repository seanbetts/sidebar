import Foundation
import sideBarShared

enum ShareExtensionMessageMapper {
    static let preparingImage = "Preparing image..."
    static let preparingFile = "Preparing file..."
    static let uploadingImage = "Uploading image..."
    static let uploadingFile = "Uploading file..."
    static let savingWebsite = "Saving website..."
    static let imageSaved = "Image saved"
    static let fileSaved = "File saved"
    static let websiteSaved = "Website saved"

    static func queueResultMessage(for item: PendingShareItem?) -> String {
        item == nil
            ? ExtensionUserMessageCatalog.message(for: .queueFailed)
            : ExtensionUserMessageCatalog.message(for: .savedForLater)
    }

    static func queueSucceeded(for item: PendingShareItem?) -> Bool {
        item != nil
    }

    static func errorMessage(for error: Error) -> String {
        if let shareError = error as? ShareExtensionError {
            switch shareError {
            case .notAuthenticated:
                return ExtensionUserMessageCatalog.message(for: .notAuthenticated)
            case .invalidBaseUrl:
                return "Invalid API base URL."
            case .invalidSharePayload:
                return ExtensionUserMessageCatalog.message(for: .invalidSharePayload)
            case .unsupportedContentType:
                return ExtensionUserMessageCatalog.message(for: .unsupportedContent)
            case .uploadFailed(let detail):
                return ExtensionUserMessageCatalog.uploadFailureMessage(detail: detail)
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return ExtensionUserMessageCatalog.message(for: .networkError)
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost:
                return ExtensionUserMessageCatalog.message(for: .networkError)
            default:
                break
            }
        }

        let detail = ExtensionUserMessageCatalog.sanitizedDetail(error.localizedDescription)
        return ExtensionUserMessageCatalog.uploadFailureMessage(detail: detail)
    }
}
