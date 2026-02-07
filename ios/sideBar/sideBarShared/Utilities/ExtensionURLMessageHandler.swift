import Foundation

public enum ExtensionURLMessageHandler {
    public static func handleSaveURLMessage(
        action: String?,
        urlString: String?,
        pendingStore: PendingShareStore = .shared
    ) -> [String: Any] {
        guard action == "save_url" else {
            return ["ok": false, "error": "Unsupported action"]
        }
        guard let urlString, !urlString.isEmpty else {
            return ["ok": false, "error": "Missing URL"]
        }
        if pendingStore.enqueueWebsite(url: urlString) != nil {
            return ["ok": true, "queued": "website"]
        }
        return ["ok": false, "error": "Failed to queue website"]
    }
}
