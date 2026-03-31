import Foundation
import sideBarShared

enum PasswordResetErrorPresentation {
    static let unavailableMessage = "Password reset is temporarily unavailable. Please try again shortly."

    static func message(for error: Error) -> String {
        if let category = URLRequestErrorClassifier.category(for: error) {
            switch category {
            case .offline:
                return "Password reset requires a connection."
            default:
                return unavailableMessage
            }
        }

        if error is APIClientError {
            return unavailableMessage
        }

        return unavailableMessage
    }
}
