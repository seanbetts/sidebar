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
                    selection: taskReminderTimeSelection,
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
                        selection: taskReminderTimeSelection,
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
        let currentPreferences = environment.settingsViewModel.settings?.notificationPreferences
        return [
            taskRemindersEnabled ? "1" : "0",
            Self.resolvedTaskReminderTimeForAutosave(
                taskRemindersEnabled: taskRemindersEnabled,
                taskReminderTime: taskReminderTime,
                hasExplicitTaskReminderTime: hasExplicitTaskReminderTime,
                currentTaskRemindersEnabled: currentPreferences?.taskRemindersEnabled ?? false
            ) ?? "",
            assistantReplyNotificationsEnabled ? "1" : "0"
        ].joined(separator: "|")
    }

    var isNotificationDraftDirty: Bool {
        guard let settings = environment.settingsViewModel.settings else { return false }
        return Self.isTaskReminderDraftDirty(
            taskRemindersEnabled: taskRemindersEnabled,
            taskReminderTime: taskReminderTime,
            hasExplicitTaskReminderTime: hasExplicitTaskReminderTime,
            currentTaskRemindersEnabled: settings.notificationPreferences.taskRemindersEnabled,
            currentTaskReminderTime: settings.notificationPreferences.taskReminderTime
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
        hasExplicitTaskReminderTime = settings.notificationPreferences.taskReminderTime != nil
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
            await performNotificationAutosaveSave()
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
            await performNotificationAutosaveSave()
        }
    }

    @MainActor
    private func performNotificationAutosaveSave() async {
        let currentPreferences = environment.settingsViewModel.settings?.notificationPreferences
        let taskReminderOutcome = await environment.settingsViewModel.saveTaskReminderSettings(
            isEnabled: taskRemindersEnabled,
            reminderTime: Self.resolvedTaskReminderTimeForAutosave(
                taskRemindersEnabled: taskRemindersEnabled,
                taskReminderTime: taskReminderTime,
                hasExplicitTaskReminderTime: hasExplicitTaskReminderTime,
                currentTaskRemindersEnabled: currentPreferences?.taskRemindersEnabled ?? false
            ),
            scheduleTimezone: Self.resolvedTaskReminderTimezoneForAutosave(
                taskRemindersEnabled: taskRemindersEnabled,
                hasExplicitTaskReminderTime: hasExplicitTaskReminderTime,
                currentTaskRemindersEnabled: currentPreferences?.taskRemindersEnabled ?? false,
                currentTimezoneIdentifier: TimeZone.autoupdatingCurrent.identifier
            )
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

    static func isTaskReminderDraftDirty(
        taskRemindersEnabled: Bool,
        taskReminderTime: Date,
        hasExplicitTaskReminderTime: Bool,
        currentTaskRemindersEnabled: Bool,
        currentTaskReminderTime: String?
    ) -> Bool {
        taskRemindersEnabled != currentTaskRemindersEnabled
            || resolvedTaskReminderTimeForAutosave(
                taskRemindersEnabled: taskRemindersEnabled,
                taskReminderTime: taskReminderTime,
                hasExplicitTaskReminderTime: hasExplicitTaskReminderTime,
                currentTaskRemindersEnabled: currentTaskRemindersEnabled
            ) != currentTaskReminderTime
    }

    static func resolvedTaskReminderTimeForAutosave(
        taskRemindersEnabled: Bool,
        taskReminderTime: Date,
        hasExplicitTaskReminderTime: Bool,
        currentTaskRemindersEnabled: Bool
    ) -> String? {
        guard taskRemindersEnabled else { return nil }
        guard hasExplicitTaskReminderTime || !currentTaskRemindersEnabled else {
            return nil
        }
        return reminderTimeString(from: taskReminderTime)
    }

    static func resolvedTaskReminderTimezoneForAutosave(
        taskRemindersEnabled: Bool,
        hasExplicitTaskReminderTime: Bool,
        currentTaskRemindersEnabled: Bool,
        currentTimezoneIdentifier: String
    ) -> String? {
        guard taskRemindersEnabled else { return nil }
        guard hasExplicitTaskReminderTime || !currentTaskRemindersEnabled else {
            return nil
        }
        return currentTimezoneIdentifier
    }

    static func defaultReminderDate() -> Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())
            ?? Date()
    }

    var taskReminderTimeSelection: Binding<Date> {
        Binding(
            get: { taskReminderTime },
            set: { newValue in
                taskReminderTime = newValue
                hasExplicitTaskReminderTime = true
            }
        )
    }
}
