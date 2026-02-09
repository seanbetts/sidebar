import Foundation

/// Enqueues shared URLs for offline processing via the pending share store.
public enum ShareExtensionURLQueueHandler {
    @discardableResult
    public static func enqueueURLForLater(
        _ url: URL,
        pendingStore: PendingShareStore = .shared
    ) -> PendingShareItem? {
        guard let normalized = ExtensionURLMessageHandler.normalizeQueuedURL(url.absoluteString) else {
            return nil
        }
        return pendingStore.enqueueWebsite(url: normalized)
    }
}
