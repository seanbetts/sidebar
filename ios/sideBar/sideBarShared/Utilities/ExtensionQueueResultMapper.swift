import Foundation

/// Converts share-queue results into user-visible status messages.
public enum ExtensionQueueResultMapper {
    public static func queueSucceeded(for item: PendingShareItem?) -> Bool {
        item != nil
    }

    public static func queueMessage(for item: PendingShareItem?) -> String {
        let code: ExtensionMessageCode = queueSucceeded(for: item) ? .savedForLater : .queueFailed
        return ExtensionUserMessageCatalog.message(for: code)
    }
}
