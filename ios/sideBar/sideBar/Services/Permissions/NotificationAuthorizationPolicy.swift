import UserNotifications

/// Centralizes notification authorization options for visible remote notifications.
public enum NotificationAuthorizationPolicy {
    /// Requests the permissions required for alert-based APNs delivery.
    public nonisolated static let visibleRemoteNotificationRequestOptions: UNAuthorizationOptions = [
        .badge,
        .alert,
        .sound
    ]
}
