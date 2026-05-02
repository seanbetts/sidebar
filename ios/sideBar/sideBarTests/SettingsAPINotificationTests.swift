import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class SettingsAPINotificationTests: XCTestCase {
    var router: ScopedURLProtocolRouter!

    override func setUp() {
        super.setUp()
        router = ScopedURLProtocolRouter()
    }

    override func tearDown() {
        router.invalidate()
        router = nil
        super.tearDown()
    }

    func testGetSettingsDecodesNotificationPreferences() async throws {
        let api = SettingsAPI(client: makeClient())
        router.setHandler { request in
            XCTAssertEqual(request.httpMethod, "GET")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = """
            {
              "user_id": "u1",
              "communication_style": null,
              "working_relationship": null,
              "name": null,
              "job_title": null,
              "employer": null,
              "date_of_birth": null,
              "gender": null,
              "pronouns": null,
              "location": null,
              "profile_image_url": null,
              "notification_preferences": {
                "task_reminders_enabled": true,
                "task_reminder_time": "09:30",
                "morning_digest_enabled": false,
                "morning_digest_time": null,
                "assistant_reply_notifications_enabled": true,
                "assistant_proactive_notifications_enabled": false,
                "schedule_timezone": "Europe/London"
              },
              "enabled_skills": []
            }
            """
            return (response, Data(payload.utf8))
        }

        let settings = try await api.getSettings()

        XCTAssertEqual(settings.notificationPreferences.taskReminderTime, "09:30")
        XCTAssertEqual(settings.notificationPreferences.scheduleTimezone, "Europe/London")
        XCTAssertTrue(settings.notificationPreferences.taskRemindersEnabled)
        XCTAssertTrue(settings.notificationPreferences.assistantReplyNotificationsEnabled)
        XCTAssertFalse(settings.notificationPreferences.morningDigestEnabled)
    }

    func testUpdateSettingsEncodesNotificationPreferencesWithSnakeCaseKeys() async throws {
        let api = SettingsAPI(client: makeClient())
        router.setHandler { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            let bodyData = try XCTUnwrap(request.httpBodyData())
            let body = try XCTUnwrap(
                JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            )
            let preferences = try XCTUnwrap(
                body["notification_preferences"] as? [String: Any]
            )
            XCTAssertEqual(preferences["task_reminders_enabled"] as? Bool, true)
            XCTAssertEqual(preferences["task_reminder_time"] as? String, "09:30")
            XCTAssertEqual(preferences["schedule_timezone"] as? String, "Europe/London")
            XCTAssertEqual(
                preferences["assistant_reply_notifications_enabled"] as? Bool,
                true
            )
            XCTAssertNil(body["notificationPreferences"])

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = """
            {
              "user_id": "u1",
              "communication_style": null,
              "working_relationship": null,
              "name": null,
              "job_title": null,
              "employer": null,
              "date_of_birth": null,
              "gender": null,
              "pronouns": null,
              "location": null,
              "profile_image_url": null,
              "notification_preferences": {
                "task_reminders_enabled": true,
                "task_reminder_time": "09:30",
                "morning_digest_enabled": false,
                "morning_digest_time": null,
                "assistant_reply_notifications_enabled": true,
                "assistant_proactive_notifications_enabled": false,
                "schedule_timezone": "Europe/London"
              },
              "enabled_skills": []
            }
            """
            return (response, Data(payload.utf8))
        }

        let settings = try await api.updateSettings(
            SettingsUpdate(
                notificationPreferences: NotificationPreferencesUpdate(
                    taskRemindersEnabled: true,
                    taskReminderTime: "09:30",
                    morningDigestEnabled: nil,
                    morningDigestTime: nil,
                    assistantReplyNotificationsEnabled: true,
                    assistantProactiveNotificationsEnabled: nil,
                    scheduleTimezone: "Europe/London"
                )
            )
        )

        XCTAssertEqual(settings.notificationPreferences.taskReminderTime, "09:30")
        XCTAssertTrue(settings.notificationPreferences.assistantReplyNotificationsEnabled)
    }

    private func makeClient(router: ScopedURLProtocolRouter? = nil) -> APIClient {
        guard let resolvedRouter = router ?? self.router else {
            fatalError("Expected scoped router to be configured before creating APIClient")
        }
        let config = APIClientConfig(
            baseUrl: resolvedRouter.baseURL,
            accessTokenProvider: { "token-123" }
        )
        let session = resolvedRouter.makeSession()
        return APIClient(config: config, session: session)
    }
}
