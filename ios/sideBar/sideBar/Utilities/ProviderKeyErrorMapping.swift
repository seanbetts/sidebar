import Foundation
import sideBarShared

extension ErrorMapping {
    public static func providerKeyMessage(for error: Error) -> String {
        if let apiError = error as? APIClientError {
            switch apiError {
            case .appError(let appError):
                if appError.category == .requestRejected {
                    return "We couldn't verify that API key. Check it and try again."
                }
                return message(for: appError)
            case .apiError(let message):
                if isInvalidProviderAPIKeyMessage(message) {
                    return "That API key doesn't look valid for this provider."
                }
                if isProviderKeyVerificationUnavailableMessage(message) {
                    return "We couldn't verify that API key right now. Please try again."
                }
                return mapAPIError(apiError)
            case .requestFailed(let status) where status == 400:
                return "We couldn't verify that API key. Check it and try again."
            default:
                break
            }
        }
        return message(for: error)
    }

    fileprivate static func isProviderKeyVerificationUnavailableMessage(_ message: String) -> Bool {
        message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            == "could not verify provider api key right now. please try again."
    }
}
