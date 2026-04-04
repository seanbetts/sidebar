import Foundation

/// Broadcasts website-save handoff changes between Apple app and extension processes.
public enum WebsiteSaveHandoffNotifier {
    private static let notificationName = CFNotificationName("ai.sidebar.sidebar.website-save-handoff" as CFString)
    private static let localNotificationName = Notification.Name("ai.sidebar.sidebar.website-save-handoff.local")

    /// Posts a cross-process website-save handoff event.
    public static func post() {
        DarwinHandoffNotifierSupport.post(
            darwinNotificationName: notificationName,
            localNotificationName: localNotificationName
        )
    }

    /// Registers a callback for cross-process website-save handoff events.
    public static func observe(_ handler: @escaping () -> Void) -> AnyObject {
        DarwinHandoffNotifierSupport.observe(
            darwinNotificationName: notificationName,
            localNotificationName: localNotificationName,
            handler: handler
        )
    }

    /// Removes a previously registered website-save handoff observer.
    public static func removeObserver(_ token: AnyObject) {
        DarwinHandoffNotifierSupport.removeObserver(
            token,
            darwinNotificationName: notificationName
        )
    }
}
