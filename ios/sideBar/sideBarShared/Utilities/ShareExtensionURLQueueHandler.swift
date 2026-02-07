import Foundation

public enum ShareExtensionURLQueueHandler {
    @discardableResult
    public static func enqueueURLForLater(
        _ url: URL,
        pendingStore: PendingShareStore = .shared
    ) -> PendingShareItem? {
        pendingStore.enqueueWebsite(url: url.absoluteString)
    }
}
