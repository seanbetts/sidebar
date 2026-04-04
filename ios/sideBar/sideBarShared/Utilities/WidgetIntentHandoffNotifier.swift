import Foundation

/// Broadcasts queued widget action handoffs between extension and app processes.
public enum WidgetIntentHandoffNotifier {
    private static let notificationName = CFNotificationName(
        "ai.sidebar.sidebar.widget-intent-handoff" as CFString
    )
    private static let localNotificationName = Notification.Name(
        "ai.sidebar.sidebar.widget-intent-handoff.local"
    )

    /// Posts a cross-process widget intent handoff event.
    public static func post() {
        DarwinHandoffNotifierSupport.post(
            darwinNotificationName: notificationName,
            localNotificationName: localNotificationName
        )
    }

    /// Registers a callback for widget intent handoff events.
    public static func observe(_ handler: @escaping () -> Void) -> AnyObject {
        DarwinHandoffNotifierSupport.observe(
            darwinNotificationName: notificationName,
            localNotificationName: localNotificationName,
            handler: handler
        )
    }

    /// Removes a previously registered widget intent handoff observer.
    public static func removeObserver(_ token: AnyObject) {
        DarwinHandoffNotifierSupport.removeObserver(
            token,
            darwinNotificationName: notificationName
        )
    }
}
