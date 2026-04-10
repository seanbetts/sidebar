import Foundation
import sideBarShared

@MainActor
extension SettingsViewModel {
    public func saveTaskReminderSettings(
        isEnabled: Bool,
        reminderTime: String?,
        scheduleTimezone: String?
    ) async {
        systemSaveError = nil
        let resolved = await currentSettingsForSave()
        guard let current = resolved.settings else { systemSaveError = resolved.error; return }

        let normalizedReminderTime = reminderTime?.trimmedOrNil
        let normalizedTimezone = scheduleTimezone?.trimmedOrNil
        if isEnabled && (normalizedReminderTime == nil || normalizedTimezone == nil) {
            systemSaveError = "Task reminders require both a reminder time and timezone."
            return
        }

        let currentPreferences = current.notificationPreferences
        let enabledUpdate = isEnabled != currentPreferences.taskRemindersEnabled ? isEnabled : nil
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
            return
        }

        isSavingSystem = true
        systemSaveError = nil
        logSettingsSaveAttempt(operation: "notifications", changedFields: [
            enabledUpdate == nil ? nil : "notification_preferences.task_reminders_enabled",
            reminderTimeUpdate == nil ? nil : "notification_preferences.task_reminder_time",
            timezoneUpdate == nil ? nil : "notification_preferences.schedule_timezone"
        ].compactMap { $0 })
        do {
            let response = try await settingsAPI.updateSettings(
                SettingsUpdate(
                    notificationPreferences: NotificationPreferencesUpdate(
                        taskRemindersEnabled: enabledUpdate,
                        taskReminderTime: reminderTimeUpdate,
                        scheduleTimezone: timezoneUpdate
                    )
                )
            )
            applySettingsResponse(response)
            settingsSaveCompletionCount += 1
        } catch {
            systemSaveError = recordSettingsSaveFailure(
                error,
                operation: "notifications"
            )
        }
        isSavingSystem = false
    }

    public func saveAssistantReplyNotificationSettings(isEnabled: Bool) async {
        systemSaveError = nil
        let resolved = await currentSettingsForSave()
        guard let current = resolved.settings else { systemSaveError = resolved.error; return }

        let currentPreferences = current.notificationPreferences
        let enabledUpdate = isEnabled != currentPreferences.assistantReplyNotificationsEnabled
            ? isEnabled
            : nil
        guard let enabledUpdate else { return }

        isSavingSystem = true
        systemSaveError = nil
        logSettingsSaveAttempt(
            operation: "notifications",
            changedFields: ["notification_preferences.assistant_reply_notifications_enabled"]
        )
        do {
            let response = try await settingsAPI.updateSettings(
                SettingsUpdate(
                    notificationPreferences: NotificationPreferencesUpdate(
                        assistantReplyNotificationsEnabled: enabledUpdate
                    )
                )
            )
            applySettingsResponse(response)
            settingsSaveCompletionCount += 1
        } catch {
            systemSaveError = recordSettingsSaveFailure(
                error,
                operation: "notifications"
            )
        }
        isSavingSystem = false
    }

    public func saveMorningDigestSettings(
        isEnabled: Bool,
        digestTime: String?,
        scheduleTimezone: String?
    ) async {
        systemSaveError = nil
        let resolved = await currentSettingsForSave()
        guard let current = resolved.settings else { systemSaveError = resolved.error; return }

        let normalizedDigestTime = digestTime?.trimmedOrNil
        let normalizedTimezone = scheduleTimezone?.trimmedOrNil
        if isEnabled && (normalizedDigestTime == nil || normalizedTimezone == nil) {
            systemSaveError = "Morning digest requires both a digest time and timezone."
            return
        }

        let currentPreferences = current.notificationPreferences
        let enabledUpdate = isEnabled != currentPreferences.morningDigestEnabled ? isEnabled : nil
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
            return
        }

        isSavingSystem = true
        systemSaveError = nil
        logSettingsSaveAttempt(operation: "notifications", changedFields: [
            enabledUpdate == nil ? nil : "notification_preferences.morning_digest_enabled",
            digestTimeUpdate == nil ? nil : "notification_preferences.morning_digest_time",
            timezoneUpdate == nil ? nil : "notification_preferences.schedule_timezone"
        ].compactMap { $0 })
        do {
            let response = try await settingsAPI.updateSettings(
                SettingsUpdate(
                    notificationPreferences: NotificationPreferencesUpdate(
                        morningDigestEnabled: enabledUpdate,
                        morningDigestTime: digestTimeUpdate,
                        scheduleTimezone: timezoneUpdate
                    )
                )
            )
            applySettingsResponse(response)
            settingsSaveCompletionCount += 1
        } catch {
            systemSaveError = recordSettingsSaveFailure(
                error,
                operation: "notifications"
            )
        }
        isSavingSystem = false
    }
}
