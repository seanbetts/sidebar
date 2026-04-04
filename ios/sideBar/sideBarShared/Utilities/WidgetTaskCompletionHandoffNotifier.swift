import Foundation

/// Broadcasts widget task completions between extension and app processes.
public enum WidgetTaskCompletionHandoffNotifier {
    private static let notificationName = CFNotificationName(
        "ai.sidebar.sidebar.widget-task-completion-handoff" as CFString
    )
    private static let localNotificationName = Notification.Name(
        "ai.sidebar.sidebar.widget-task-completion-handoff.local"
    )

    /// Posts a cross-process widget task completion event.
    public static func post() {
        DarwinHandoffNotifierSupport.post(
            darwinNotificationName: notificationName,
            localNotificationName: localNotificationName
        )
    }

    /// Registers a callback for widget task completion events.
    public static func observe(_ handler: @escaping () -> Void) -> AnyObject {
        DarwinHandoffNotifierSupport.observe(
            darwinNotificationName: notificationName,
            localNotificationName: localNotificationName,
            handler: handler
        )
    }

    /// Removes a previously registered task completion observer.
    public static func removeObserver(_ token: AnyObject) {
        DarwinHandoffNotifierSupport.removeObserver(
            token,
            darwinNotificationName: notificationName
        )
    }
}
