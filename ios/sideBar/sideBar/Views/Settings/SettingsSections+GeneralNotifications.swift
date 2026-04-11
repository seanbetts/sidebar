import Foundation
import SwiftUI

extension GeneralSettingsView {
    @ViewBuilder
    var notificationIOSSections: some View {
        Section {
            Toggle("Daily task reminders", isOn: $taskRemindersEnabled)
            if Self.shouldShowTaskReminderTimeControl(taskRemindersEnabled: taskRemindersEnabled) {
                DatePicker(
                    "Reminder time",
                    selection: $taskReminderTime,
                    displayedComponents: .hourAndMinute
                )
            }
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Task Reminders")
                Text(Self.taskReminderSectionSubtitle)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if Self.shouldShowMorningDigestControls {
            Section {
                EmptyView()
            } header: {
                EmptyView()
            }
        }

        Section {
            Toggle("Assistant reply notifications", isOn: $assistantReplyNotificationsEnabled)
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Assistant Replies")
                Text(Self.assistantRepliesSectionSubtitle)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    var notificationMacSections: some View {
        SettingsMacPanelCard {
            SettingsMacSectionIntro(
                title: "Task reminders",
                message: Self.taskReminderSectionSubtitle
            )
            Toggle("Daily task reminders", isOn: $taskRemindersEnabled)
            if Self.shouldShowTaskReminderTimeControl(taskRemindersEnabled: taskRemindersEnabled) {
                SettingsMacFieldRow("Reminder time") {
                    DatePicker(
                        "Reminder time",
                        selection: $taskReminderTime,
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                }
            }
        }

        if Self.shouldShowMorningDigestControls {
            EmptyView()
        }

        SettingsMacPanelCard {
            SettingsMacSectionIntro(
                title: "Assistant replies",
                message: Self.assistantRepliesSectionSubtitle
            )
            Toggle("Assistant reply notifications", isOn: $assistantReplyNotificationsEnabled)
        }
    }

    var notificationSettingsSignature: String {
        guard let settings = environment.settingsViewModel.settings else {
            return "none"
        }
        return [
            settings.userId,
            settings.notificationPreferences.taskRemindersEnabled ? "1" : "0",
            settings.notificationPreferences.taskReminderTime ?? "",
            settings.notificationPreferences.assistantReplyNotificationsEnabled ? "1" : "0"
        ].joined(separator: "|")
    }

    var notificationAutosaveSignature: String {
        [
            taskRemindersEnabled ? "1" : "0",
            Self.reminderTimeString(from: taskReminderTime),
            assistantReplyNotificationsEnabled ? "1" : "0"
        ].joined(separator: "|")
    }

    var isNotificationDraftDirty: Bool {
        guard let settings = environment.settingsViewModel.settings else { return false }
        return taskRemindersEnabled != settings.notificationPreferences.taskRemindersEnabled
            || (
                taskRemindersEnabled
                && Self.reminderTimeString(from: taskReminderTime)
                    != settings.notificationPreferences.taskReminderTime
            )
            || assistantReplyNotificationsEnabled
                != settings.notificationPreferences.assistantReplyNotificationsEnabled
    }

    func syncNotificationDraftsFromSettings(_ settings: UserSettings?) {
        guard let settings else { return }
        let shouldSync = SettingsDraftSynchronizer.shouldSyncDrafts(
            hasLoadedDrafts: hasLoadedNotificationDrafts,
            isDraftDirty: isNotificationDraftDirty,
            previousUserId: notificationDraftsUserId,
            nextUserId: settings.userId
        )
        if !shouldSync {
            return
        }
        if SettingsDraftSynchronizer.normalizedUserId(notificationDraftsUserId)
            != SettingsDraftSynchronizer.normalizedUserId(settings.userId) {
            notificationAutosaveController.cancelPendingAutosave()
        }
        isSyncingNotificationDrafts = true
        taskRemindersEnabled = settings.notificationPreferences.taskRemindersEnabled
        taskReminderTime = Self.reminderDate(
            from: settings.notificationPreferences.taskReminderTime
        )
        assistantReplyNotificationsEnabled = settings.notificationPreferences.assistantReplyNotificationsEnabled
        notificationDraftsUserId = settings.userId
        hasLoadedNotificationDrafts = true
        isSyncingNotificationDrafts = false
    }

    func scheduleNotificationAutosave() {
        notificationAutosaveController.scheduleAutosave(
            hasLoadedDrafts: hasLoadedNotificationDrafts,
            isSyncingDrafts: isSyncingNotificationDrafts,
            isDraftDirty: isNotificationDraftDirty
        ) {
            let taskReminderOutcome = await environment.settingsViewModel.saveTaskReminderSettings(
                isEnabled: taskRemindersEnabled,
                reminderTime: taskRemindersEnabled
                    ? Self.reminderTimeString(from: taskReminderTime)
                    : nil,
                scheduleTimezone: taskRemindersEnabled
                    ? TimeZone.autoupdatingCurrent.identifier
                    : nil
            )
            if taskReminderOutcome == .blockedBySystemPermission {
                syncNotificationDraftsFromSettings(environment.settingsViewModel.settings)
                return
            }
            let assistantRepliesOutcome = await environment.settingsViewModel
                .saveAssistantReplyNotificationSettings(
                isEnabled: assistantReplyNotificationsEnabled
            )
            if assistantRepliesOutcome == .blockedBySystemPermission {
                syncNotificationDraftsFromSettings(environment.settingsViewModel.settings)
            }
        }
    }

    func flushPendingNotificationAutosave() {
        let canFlush = Self.shouldFlushNotificationAutosaveOnDisappear(
            hasLoadedDrafts: hasLoadedNotificationDrafts,
            isSyncingDrafts: isSyncingNotificationDrafts,
            isDraftDirty: isNotificationDraftDirty,
            isSavingSystem: environment.settingsViewModel.isSavingSystem,
            isAutosaveSaving: notificationAutosaveController.isAutosaveSaving
        )
        notificationAutosaveController.flushPendingAutosave(
            shouldFlush: canFlush
        ) {
            let taskReminderOutcome = await environment.settingsViewModel.saveTaskReminderSettings(
                isEnabled: taskRemindersEnabled,
                reminderTime: taskRemindersEnabled
                    ? Self.reminderTimeString(from: taskReminderTime)
                    : nil,
                scheduleTimezone: taskRemindersEnabled
                    ? TimeZone.autoupdatingCurrent.identifier
                    : nil
            )
            if taskReminderOutcome == .blockedBySystemPermission {
                syncNotificationDraftsFromSettings(environment.settingsViewModel.settings)
                return
            }
            let assistantRepliesOutcome = await environment.settingsViewModel
                .saveAssistantReplyNotificationSettings(
                isEnabled: assistantReplyNotificationsEnabled
            )
            if assistantRepliesOutcome == .blockedBySystemPermission {
                syncNotificationDraftsFromSettings(environment.settingsViewModel.settings)
            }
        }
    }

    static func shouldShowTaskReminderTimeControl(taskRemindersEnabled: Bool) -> Bool {
        taskRemindersEnabled
    }

    static var shouldShowMorningDigestControls: Bool {
        false
    }

    static var taskReminderSectionSubtitle: String {
        """
        Choose whether sideBar sends one daily reminder for due and overdue tasks.
        Reminders send once a day and still follow your Apple notification settings.
        """
    }

    static var assistantRepliesSectionSubtitle: String {
        """
        Get a notification when the assistant finishes a reply while you are away.
        sideBar only sends these when a reply is ready and your device is away.
        """
    }

    static func shouldFlushNotificationAutosaveOnDisappear(
        hasLoadedDrafts: Bool,
        isSyncingDrafts: Bool,
        isDraftDirty: Bool,
        isSavingSystem: Bool,
        isAutosaveSaving: Bool = false
    ) -> Bool {
        hasLoadedDrafts
            && !isSyncingDrafts
            && isDraftDirty
            && !isSavingSystem
            && !isAutosaveSaving
    }

    static func reminderDate(from time: String?) -> Date {
        guard let time else { return defaultReminderDate() }
        let parts = time.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              let date = Calendar.current.date(
                bySettingHour: hour,
                minute: minute,
                second: 0,
                of: Date()
              ) else {
            return defaultReminderDate()
        }
        return date
    }

    static func reminderTimeString(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 9
        let minute = components.minute ?? 0
        return String(format: "%02d:%02d", hour, minute)
    }

    static func defaultReminderDate() -> Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())
            ?? Date()
    }
}
