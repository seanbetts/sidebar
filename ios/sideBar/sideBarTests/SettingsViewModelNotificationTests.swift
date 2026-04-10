import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class SettingsViewModelNotificationTests: XCTestCase {
    func testSaveTaskReminderSettingsPersistsReminderTimeAndTimezone() async {
        let initial = makeSettings(
            notificationPreferences: NotificationPreferencesSettings(
                taskRemindersEnabled: false,
                taskReminderTime: nil,
                morningDigestEnabled: true,
                morningDigestTime: "08:00",
                assistantReplyNotificationsEnabled: false,
                assistantProactiveNotificationsEnabled: false,
                scheduleTimezone: "Europe/London"
            )
        )
        let updated = makeSettings(
            notificationPreferences: NotificationPreferencesSettings(
                taskRemindersEnabled: true,
                taskReminderTime: "09:30",
                morningDigestEnabled: true,
                morningDigestTime: "08:00",
                assistantReplyNotificationsEnabled: false,
                assistantProactiveNotificationsEnabled: false,
                scheduleTimezone: "Europe/London"
            )
        )
        let recorder = UpdateRecorder()
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(
                result: .success(initial),
                updateResult: .success(updated),
                updateRecorder: recorder
            ),
            skillsAPI: MockSkillsAPI(result: .failure(SettingsViewModelMockError.forced)),
            cache: TestCacheClient()
        )
        viewModel.applySettingsResponse(initial)

        await viewModel.saveTaskReminderSettings(
            isEnabled: true,
            reminderTime: "09:30",
            scheduleTimezone: "Europe/London"
        )

        XCTAssertEqual(recorder.callCount, 1)
        XCTAssertEqual(
            recorder.lastUpdate?.notificationPreferences?.taskReminderTime,
            "09:30"
        )
        XCTAssertEqual(
            recorder.lastUpdate?.notificationPreferences?.scheduleTimezone,
            "Europe/London"
        )
        XCTAssertTrue(recorder.lastUpdate?.notificationPreferences?.taskRemindersEnabled == true)
        XCTAssertEqual(viewModel.settings?.notificationPreferences.taskReminderTime, "09:30")
        XCTAssertTrue(viewModel.settings?.notificationPreferences.morningDigestEnabled == true)
    }

    func testSaveTaskReminderSettingsRejectsEnableWithoutTimeAndTimezone() async {
        let initial = makeSettings()
        let recorder = UpdateRecorder()
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(
                result: .success(initial),
                updateRecorder: recorder
            ),
            skillsAPI: MockSkillsAPI(result: .failure(SettingsViewModelMockError.forced)),
            cache: TestCacheClient()
        )
        viewModel.applySettingsResponse(initial)

        await viewModel.saveTaskReminderSettings(
            isEnabled: true,
            reminderTime: nil,
            scheduleTimezone: nil
        )

        XCTAssertEqual(recorder.callCount, 0)
        XCTAssertEqual(
            viewModel.systemSaveError,
            "Task reminders require both a reminder time and timezone."
        )
        XCTAssertFalse(viewModel.isSavingSystem)
    }

    func testSaveAssistantReplyNotificationSettingsPersistsToggle() async {
        let initial = makeSettings(
            notificationPreferences: NotificationPreferencesSettings(
                taskRemindersEnabled: true,
                taskReminderTime: "09:30",
                morningDigestEnabled: false,
                morningDigestTime: nil,
                assistantReplyNotificationsEnabled: false,
                assistantProactiveNotificationsEnabled: false,
                scheduleTimezone: "Europe/London"
            )
        )
        let updated = makeSettings(
            notificationPreferences: NotificationPreferencesSettings(
                taskRemindersEnabled: true,
                taskReminderTime: "09:30",
                morningDigestEnabled: false,
                morningDigestTime: nil,
                assistantReplyNotificationsEnabled: true,
                assistantProactiveNotificationsEnabled: false,
                scheduleTimezone: "Europe/London"
            )
        )
        let recorder = UpdateRecorder()
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(
                result: .success(initial),
                updateResult: .success(updated),
                updateRecorder: recorder
            ),
            skillsAPI: MockSkillsAPI(result: .failure(SettingsViewModelMockError.forced)),
            cache: TestCacheClient()
        )
        viewModel.applySettingsResponse(initial)

        await viewModel.saveAssistantReplyNotificationSettings(isEnabled: true)

        XCTAssertEqual(recorder.callCount, 1)
        XCTAssertTrue(
            recorder.lastUpdate?.notificationPreferences?.assistantReplyNotificationsEnabled == true
        )
        XCTAssertTrue(viewModel.settings?.notificationPreferences.assistantReplyNotificationsEnabled == true)
        XCTAssertEqual(
            viewModel.settings?.notificationPreferences.taskReminderTime,
            "09:30"
        )
    }

    func testSaveMorningDigestSettingsPersistsDigestTimeAndTimezone() async {
        let initial = makeSettings(
            notificationPreferences: NotificationPreferencesSettings(
                taskRemindersEnabled: true,
                taskReminderTime: "09:30",
                morningDigestEnabled: false,
                morningDigestTime: nil,
                assistantReplyNotificationsEnabled: false,
                assistantProactiveNotificationsEnabled: false,
                scheduleTimezone: "Europe/London"
            )
        )
        let updated = makeSettings(
            notificationPreferences: NotificationPreferencesSettings(
                taskRemindersEnabled: true,
                taskReminderTime: "09:30",
                morningDigestEnabled: true,
                morningDigestTime: "08:15",
                assistantReplyNotificationsEnabled: false,
                assistantProactiveNotificationsEnabled: false,
                scheduleTimezone: "Europe/London"
            )
        )
        let recorder = UpdateRecorder()
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(
                result: .success(initial),
                updateResult: .success(updated),
                updateRecorder: recorder
            ),
            skillsAPI: MockSkillsAPI(result: .failure(SettingsViewModelMockError.forced)),
            cache: TestCacheClient()
        )
        viewModel.applySettingsResponse(initial)

        await viewModel.saveMorningDigestSettings(
            isEnabled: true,
            digestTime: "08:15",
            scheduleTimezone: "Europe/London"
        )

        XCTAssertEqual(recorder.callCount, 1)
        XCTAssertTrue(recorder.lastUpdate?.notificationPreferences?.morningDigestEnabled == true)
        XCTAssertEqual(
            recorder.lastUpdate?.notificationPreferences?.morningDigestTime,
            "08:15"
        )
        XCTAssertEqual(
            recorder.lastUpdate?.notificationPreferences?.scheduleTimezone,
            "Europe/London"
        )
        XCTAssertTrue(viewModel.settings?.notificationPreferences.morningDigestEnabled == true)
        XCTAssertEqual(viewModel.settings?.notificationPreferences.morningDigestTime, "08:15")
    }

    func testSaveMorningDigestSettingsRejectsEnableWithoutTimeAndTimezone() async {
        let initial = makeSettings()
        let recorder = UpdateRecorder()
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(
                result: .success(initial),
                updateRecorder: recorder
            ),
            skillsAPI: MockSkillsAPI(result: .failure(SettingsViewModelMockError.forced)),
            cache: TestCacheClient()
        )
        viewModel.applySettingsResponse(initial)

        await viewModel.saveMorningDigestSettings(
            isEnabled: true,
            digestTime: nil,
            scheduleTimezone: nil
        )

        XCTAssertEqual(recorder.callCount, 0)
        XCTAssertEqual(
            viewModel.systemSaveError,
            "Morning digest requires both a digest time and timezone."
        )
        XCTAssertFalse(viewModel.isSavingSystem)
    }

    private func makeSettings(
        notificationPreferences: NotificationPreferencesSettings = .defaults
    ) -> UserSettings {
        UserSettings(
            userId: "user-1",
            communicationStyle: nil,
            workingRelationship: nil,
            name: "User",
            jobTitle: nil,
            employer: nil,
            dateOfBirth: nil,
            gender: nil,
            pronouns: nil,
            location: nil,
            profileImageUrl: nil,
            notificationPreferences: notificationPreferences,
            enabledSkills: []
        )
    }
}
