import Foundation

/// Routes Safari web extension messages into pending-share responses.
public enum SafariExtensionMessageHandler {
    public static func responsePayload(
        for message: Any?,
        pendingStore: PendingShareStore = .shared,
        saveWebsite: ((String) async throws -> Void)? = nil,
        refreshAccessToken: (() async -> Bool)? = nil
    ) async -> [String: Any] {
        let payload = message as? [String: Any]
        let action = payload?["action"] as? String
        let urlString = payload?["url"] as? String
        return await ExtensionURLMessageHandler.handleSaveURLMessage(
            action: action,
            urlString: urlString,
            pendingStore: pendingStore,
            saveWebsite: saveWebsite,
            refreshAccessToken: refreshAccessToken
        )
    }
}
