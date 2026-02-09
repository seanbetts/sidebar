import Foundation

/// Routes Safari web extension messages into pending-share responses.
public enum SafariExtensionMessageHandler {
    public static func responsePayload(
        for message: Any?,
        pendingStore: PendingShareStore = .shared
    ) -> [String: Any] {
        let payload = message as? [String: Any]
        let action = payload?["action"] as? String
        let urlString = payload?["url"] as? String
        return ExtensionURLMessageHandler.handleSaveURLMessage(
            action: action,
            urlString: urlString,
            pendingStore: pendingStore
        )
    }
}
