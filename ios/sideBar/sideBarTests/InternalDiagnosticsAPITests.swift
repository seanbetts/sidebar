import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class InternalDiagnosticsAPITests: XCTestCase {
    private var router: ScopedURLProtocolRouter!

    override func setUp() {
        super.setUp()
        router = ScopedURLProtocolRouter()
    }

    override func tearDown() {
        router.invalidate()
        router = nil
        super.tearDown()
    }

    func testGetSnapshotDecodesDiagnosticsPayload() async throws {
        let api = InternalDiagnosticsAPI(client: makeClient())
        router.setHandler { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("notification-diagnostics") == true)
            return try snapshotResponse(for: request.url)
        }

        let snapshot = try await api.getSnapshot()

        XCTAssertTrue(snapshot.canAccessInternalDiagnostics)
        XCTAssertEqual(snapshot.accountSummary?.userId, "user-123")
        XCTAssertEqual(snapshot.scheduler?.workerName, "notification_schedule")
        XCTAssertEqual(snapshot.scheduler?.lastTaskRemindersDispatched, 2)
        XCTAssertEqual(snapshot.schedulerRuns.count, 1)
        XCTAssertEqual(snapshot.schedulerRuns.first?.status, "completed")
        XCTAssertEqual(snapshot.installations.count, 1)
        XCTAssertEqual(snapshot.recentDelivery.count, 1)
        XCTAssertEqual(snapshot.recentSchedulerDecisions.count, 1)
        XCTAssertEqual(snapshot.recentSchedulerDecisions.first?.decisionReason, "no_reminder_intent")
        XCTAssertEqual(snapshot.installations.first?.tokenSuffix, "abcdef")
    }

    func testSendTestPushPostsInstallationId() async throws {
        let api = InternalDiagnosticsAPI(client: makeClient())
        router.setHandler { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("installations/install-123/test-push") == true)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(#"{"installation_id":"install-123","accepted":true}"#.utf8))
        }

        let response = try await api.sendTestPush(installationId: "install-123")

        XCTAssertEqual(response.installationId, "install-123")
        XCTAssertTrue(response.accepted)
    }

    private func makeClient() -> APIClient {
        APIClient(
            config: APIClientConfig(
                baseUrl: router.baseURL,
                accessTokenProvider: { nil }
            ),
            session: router.makeSession()
        )
    }

    private func snapshotResponse(for url: URL?) throws -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: try XCTUnwrap(url),
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, Data(snapshotPayload.utf8))
    }

    private var snapshotPayload: String {
        """
        {
          "can_access_internal_diagnostics": true,
          "account_summary": {
            "user_id": "user-123"
          },
          "scheduler": {
            "worker_name": "notification_schedule",
            "last_started_at": "2026-04-20T08:00:00Z",
            "last_completed_at": "2026-04-20T08:00:01Z",
            "last_status": "completed",
            "last_error": null,
            "last_task_reminders_due": 2,
            "last_task_reminders_dispatched": 2,
            "last_morning_digests_due": 0,
            "last_morning_digests_dispatched": 0
          },
          "scheduler_runs": [
            {
              "worker_name": "notification_schedule",
              "started_at": "2026-04-20T08:00:00Z",
              "completed_at": "2026-04-20T08:00:01Z",
              "status": "completed",
              "error": null,
              "task_reminders_due": 2,
              "task_reminders_dispatched": 2,
              "morning_digests_due": 0,
              "morning_digests_dispatched": 0
            }
          ],
          "installations": [
            {
              "installation_id": "install-123",
              "user_id": "user-123",
              "platform": "ios",
              "token_suffix": "abcdef",
              "is_foreground": true
            }
          ],
          "recent_delivery": [
            {
              "created_at": "2026-04-19T10:00:00Z",
              "user_id": "user-123",
              "installation_id": "install-123",
              "notification_kind": "reminder",
              "platform": "ios",
              "token_suffix": "abcdef",
              "delivery_result": "sent"
            }
          ],
          "recent_scheduler_decisions": [
            {
              "created_at": "2026-04-20T08:00:00Z",
              "run_started_at": "2026-04-20T08:00:00Z",
              "user_id": "user-123",
              "notification_kind": "task_reminder",
              "decision_stage": "dispatch",
              "decision_reason": "no_reminder_intent",
              "scheduled_time": "09:00",
              "schedule_timezone": "Europe/London",
              "local_now": "2026-04-20T09:00:00+01:00",
              "detail": "no_due_tasks"
            }
          ]
        }
        """
    }
}
