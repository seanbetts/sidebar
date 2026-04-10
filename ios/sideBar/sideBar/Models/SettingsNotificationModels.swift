import Foundation

/// Notification preferences persisted for the current user.
public struct NotificationPreferencesSettings: Codable, Equatable {
    public let taskRemindersEnabled: Bool
    public let taskReminderTime: String?
    public let morningDigestEnabled: Bool
    public let morningDigestTime: String?
    public let assistantReplyNotificationsEnabled: Bool
    public let assistantProactiveNotificationsEnabled: Bool
    public let scheduleTimezone: String?

    public init(
        taskRemindersEnabled: Bool,
        taskReminderTime: String?,
        morningDigestEnabled: Bool,
        morningDigestTime: String?,
        assistantReplyNotificationsEnabled: Bool,
        assistantProactiveNotificationsEnabled: Bool,
        scheduleTimezone: String?
    ) {
        self.taskRemindersEnabled = taskRemindersEnabled
        self.taskReminderTime = taskReminderTime
        self.morningDigestEnabled = morningDigestEnabled
        self.morningDigestTime = morningDigestTime
        self.assistantReplyNotificationsEnabled = assistantReplyNotificationsEnabled
        self.assistantProactiveNotificationsEnabled = assistantProactiveNotificationsEnabled
        self.scheduleTimezone = scheduleTimezone
    }

    public static let defaults = NotificationPreferencesSettings(
        taskRemindersEnabled: true,
        taskReminderTime: nil,
        morningDigestEnabled: false,
        morningDigestTime: nil,
        assistantReplyNotificationsEnabled: false,
        assistantProactiveNotificationsEnabled: false,
        scheduleTimezone: nil
    )
}

/// Notification preference updates sent to the backend.
public struct NotificationPreferencesUpdate: Encodable, Equatable {
    public let taskRemindersEnabled: Bool?
    public let taskReminderTime: String?
    public let morningDigestEnabled: Bool?
    public let morningDigestTime: String?
    public let assistantReplyNotificationsEnabled: Bool?
    public let assistantProactiveNotificationsEnabled: Bool?
    public let scheduleTimezone: String?

    public init(
        taskRemindersEnabled: Bool? = nil,
        taskReminderTime: String? = nil,
        morningDigestEnabled: Bool? = nil,
        morningDigestTime: String? = nil,
        assistantReplyNotificationsEnabled: Bool? = nil,
        assistantProactiveNotificationsEnabled: Bool? = nil,
        scheduleTimezone: String? = nil
    ) {
        self.taskRemindersEnabled = taskRemindersEnabled
        self.taskReminderTime = taskReminderTime
        self.morningDigestEnabled = morningDigestEnabled
        self.morningDigestTime = morningDigestTime
        self.assistantReplyNotificationsEnabled = assistantReplyNotificationsEnabled
        self.assistantProactiveNotificationsEnabled = assistantProactiveNotificationsEnabled
        self.scheduleTimezone = scheduleTimezone
    }

    private enum CodingKeys: String, CodingKey {
        case taskRemindersEnabled = "task_reminders_enabled"
        case taskReminderTime = "task_reminder_time"
        case morningDigestEnabled = "morning_digest_enabled"
        case morningDigestTime = "morning_digest_time"
        case assistantReplyNotificationsEnabled = "assistant_reply_notifications_enabled"
        case assistantProactiveNotificationsEnabled = "assistant_proactive_notifications_enabled"
        case scheduleTimezone = "schedule_timezone"
    }
}
