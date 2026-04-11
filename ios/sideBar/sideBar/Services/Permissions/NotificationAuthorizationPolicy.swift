import UserNotifications

/// Centralizes notification authorization options for visible remote notifications.
public enum NotificationAuthorizationPolicy {
    /// Requests the permissions required for alert-based APNs delivery.
    public nonisolated static let visibleRemoteNotificationRequestOptions: UNAuthorizationOptions = [
        .badge,
        .alert,
        .sound
    ]

    /// Returns true when the app should issue a visible-notification authorization request.
    public nonisolated static func shouldRequestVisibleRemoteNotificationAuthorization(
        for status: UNAuthorizationStatus
    ) -> Bool {
        switch status {
        case .notDetermined, .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    /// Returns true when notification authorization is already granted at the system level.
    public nonisolated static func isVisibleRemoteNotificationAuthorized(
        _ status: UNAuthorizationStatus
    ) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }
}
