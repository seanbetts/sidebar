import Foundation
import sideBarShared

enum WebsiteURLValidator {
    static func isValid(_ input: String) -> Bool {
        normalizedCandidate(input) != nil
    }

    static func normalizedCandidate(_ input: String) -> URL? {
        guard let normalized = ExtensionURLMessageHandler.normalizeQueuedURL(input) else {
            return nil
        }
        return URL(string: normalized)
    }
}
