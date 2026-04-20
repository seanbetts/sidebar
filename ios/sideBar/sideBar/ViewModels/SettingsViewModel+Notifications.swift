import Foundation
import sideBarShared

/// Describes the result of a notification-settings save attempt.
public enum NotificationSettingsSaveOutcome: Equatable {
    case persisted
    case noChange
    case blockedBySystemPermission
    case failed
}

@MainActor
extension SettingsViewModel {
    @discardableResult
    public func saveTaskReminderSettings(
        isEnabled: Bool,
        reminderTime: String?,
        scheduleTimezone: String?
    ) async -> NotificationSettingsSaveOutcome {
        systemSaveError = nil
        let resolved = await currentSettingsForSave()
        guard let current = resolved.settings else {
            systemSaveError = resolved.error
            return .failed
        }

        let normalizedReminderTime = reminderTime?.trimmedOrNil
        let normalizedTimezone = scheduleTimezone?.trimmedOrNil
        if isEnabled && (normalizedReminderTime == nil || normalizedTimezone == nil) {
            systemSaveError = "Task reminders require both a reminder time and timezone."
            return .failed
        }

        let currentPreferences = current.notificationPreferences
        let enabledUpdate = isEnabled != currentPreferences.taskRemindersEnabled ? isEnabled : nil
        if enabledUpdate == true {
            let permissionState = await notificationPermissionRequester.requestPermission()
            guard permissionState == .granted else {
                systemSaveError = "Allow notifications in Apple Settings before enabling reminders."
                return .blockedBySystemPermission
            }
        }
        let shouldForceSchedulePayload = isEnabled && enabledUpdate == true
        let reminderTimeUpdate: String?
        if shouldForceSchedulePayload {
            reminderTimeUpdate = normalizedReminderTime
        } else if normalizedReminderTime != currentPreferences.taskReminderTime {
            reminderTimeUpdate = normalizedReminderTime
        } else {
            reminderTimeUpdate = nil
        }

        let timezoneUpdate: String?
        if shouldForceSchedulePayload {
            timezoneUpdate = normalizedTimezone
        } else if normalizedTimezone != currentPreferences.scheduleTimezone {
            timezoneUpdate = normalizedTimezone
        } else {
            timezoneUpdate = nil
        }

        if enabledUpdate == nil, reminderTimeUpdate == nil, timezoneUpdate == nil {
            return .noChange
        }

        isSavingSystem = true
        systemSaveError = nil
        logSettingsSaveAttempt(operation: "notifications", changedFields: [
            enabledUpdate == nil ? nil : "notification_preferences.task_reminders_enabled",
            reminderTimeUpdate == nil ? nil : "notification_preferences.task_reminder_time",
            timezoneUpdate == nil ? nil : "notification_preferences.schedule_timezone"
        ].compactMap { $0 })
        do {
            try await commitSettingsPatch(
                SettingsMutationPayload(
                    notificationPreferences: NotificationPreferencesUpdate(
                        taskRemindersEnabled: enabledUpdate,
                        taskReminderTime: reminderTimeUpdate,
                        scheduleTimezone: timezoneUpdate
                    )
                )
            )
        } catch {
            systemSaveError = recordSettingsSaveFailure(
                error,
                operation: "notifications"
            )
            isSavingSystem = false
            return .failed
        }
        isSavingSystem = false
        return .persisted
    }

    @discardableResult
    public func saveAssistantReplyNotificationSettings(
        isEnabled: Bool
    ) async -> NotificationSettingsSaveOutcome {
        systemSaveError = nil
        let resolved = await currentSettingsForSave()
        guard let current = resolved.settings else {
            systemSaveError = resolved.error
            return .failed
        }

        let currentPreferences = current.notificationPreferences
        let enabledUpdate = isEnabled != currentPreferences.assistantReplyNotificationsEnabled
            ? isEnabled
            : nil
        guard let enabledUpdate else { return .noChange }
        if enabledUpdate {
            let permissionState = await notificationPermissionRequester.requestPermission()
            guard permissionState == .granted else {
                systemSaveError = "Allow notifications in Apple Settings before enabling reminders."
                return .blockedBySystemPermission
            }
        }

        isSavingSystem = true
        systemSaveError = nil
        logSettingsSaveAttempt(
            operation: "notifications",
            changedFields: ["notification_preferences.assistant_reply_notifications_enabled"]
        )
        do {
            try await commitSettingsPatch(
                SettingsMutationPayload(
                    notificationPreferences: NotificationPreferencesUpdate(
                        assistantReplyNotificationsEnabled: enabledUpdate
                    )
                )
            )
        } catch {
            systemSaveError = recordSettingsSaveFailure(
                error,
                operation: "notifications"
            )
            isSavingSystem = false
            return .failed
        }
        isSavingSystem = false
        return .persisted
    }

    @discardableResult
    public func saveMorningDigestSettings(
        isEnabled: Bool,
        digestTime: String?,
        scheduleTimezone: String?
    ) async -> NotificationSettingsSaveOutcome {
        systemSaveError = nil
        let resolved = await currentSettingsForSave()
        guard let current = resolved.settings else {
            systemSaveError = resolved.error
            return .failed
        }

        let normalizedDigestTime = digestTime?.trimmedOrNil
        let normalizedTimezone = scheduleTimezone?.trimmedOrNil
        if isEnabled && (normalizedDigestTime == nil || normalizedTimezone == nil) {
            systemSaveError = "Morning digest requires both a digest time and timezone."
            return .failed
        }

        let currentPreferences = current.notificationPreferences
        let enabledUpdate = isEnabled != currentPreferences.morningDigestEnabled ? isEnabled : nil
        if enabledUpdate == true {
            let permissionState = await notificationPermissionRequester.requestPermission()
            guard permissionState == .granted else {
                systemSaveError = "Allow notifications in Apple Settings before enabling reminders."
                return .blockedBySystemPermission
            }
        }
        let shouldForceSchedulePayload = isEnabled && enabledUpdate == true
        let digestTimeUpdate: String?
        if shouldForceSchedulePayload {
            digestTimeUpdate = normalizedDigestTime
        } else if normalizedDigestTime != currentPreferences.morningDigestTime {
            digestTimeUpdate = normalizedDigestTime
        } else {
            digestTimeUpdate = nil
        }

        let timezoneUpdate: String?
        if shouldForceSchedulePayload {
            timezoneUpdate = normalizedTimezone
        } else if normalizedTimezone != currentPreferences.scheduleTimezone {
            timezoneUpdate = normalizedTimezone
        } else {
            timezoneUpdate = nil
        }

        if enabledUpdate == nil, digestTimeUpdate == nil, timezoneUpdate == nil {
            return .noChange
        }

        isSavingSystem = true
        systemSaveError = nil
        logSettingsSaveAttempt(operation: "notifications", changedFields: [
            enabledUpdate == nil ? nil : "notification_preferences.morning_digest_enabled",
            digestTimeUpdate == nil ? nil : "notification_preferences.morning_digest_time",
            timezoneUpdate == nil ? nil : "notification_preferences.schedule_timezone"
        ].compactMap { $0 })
        do {
            try await commitSettingsPatch(
                SettingsMutationPayload(
                    notificationPreferences: NotificationPreferencesUpdate(
                        morningDigestEnabled: enabledUpdate,
                        morningDigestTime: digestTimeUpdate,
                        scheduleTimezone: timezoneUpdate
                    )
                )
            )
        } catch {
            systemSaveError = recordSettingsSaveFailure(
                error,
                operation: "notifications"
            )
            isSavingSystem = false
            return .failed
        }
        isSavingSystem = false
        return .persisted
    }
}
