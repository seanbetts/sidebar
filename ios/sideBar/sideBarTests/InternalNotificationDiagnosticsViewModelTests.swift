import XCTest
@testable import sideBar

@MainActor
final class InternalDiagnosticsViewModelTests: XCTestCase {
    func testRefreshLoadsSnapshot() async throws {
        let snapshot = InternalNotificationDiagnosticsSnapshot(
            canAccessInternalDiagnostics: true,
            accountSummary: NotificationDiagnosticsAccountSummary(userId: "user-123"),
            scheduler: nil,
            schedulerRuns: [],
            installations: [
                NotificationDiagnosticsInstallationRow(
                    installationId: "install-123",
                    userId: "user-123",
                    platform: "ios",
                    tokenSuffix: "abcdef",
                    isForeground: true
                )
            ],
            recentDelivery: [],
            recentSchedulerDecisions: []
        )
        let api = MockInternalDiagnosticsAPI(snapshotResult: .success(snapshot))
        let viewModel = InternalNotificationDiagnosticsViewModel(
            diagnosticsAPI: api,
            localStateProvider: { PushLifecycleDiagnosticsState(currentDeviceInstallationId: "install-123") },
            reregisterCurrentDevice: {}
        )

        await viewModel.refresh()

        XCTAssertEqual(api.getSnapshotCallCount, 1)
        XCTAssertEqual(viewModel.snapshot, snapshot)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testSendTestPushUsesCurrentDeviceInstallationId() async throws {
        let api = MockInternalDiagnosticsAPI(
            testPushResult: .success(
                InternalNotificationTestPushResponse(
                    installationId: "install-123",
                    accepted: true,
                    message: "accepted"
                )
            )
        )
        let viewModel = InternalNotificationDiagnosticsViewModel(
            diagnosticsAPI: api,
            localStateProvider: { PushLifecycleDiagnosticsState(currentDeviceInstallationId: "install-123") },
            reregisterCurrentDevice: {}
        )

        await viewModel.sendTestPushToCurrentInstallation()

        XCTAssertEqual(api.sendTestPushInstallationIds, ["install-123"])
        XCTAssertEqual(viewModel.lastTestPushResponse?.installationId, "install-123")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isSendingTestPush)
    }

    func testReRegisterThisDeviceInvokesProvidedAction() async {
        let counter = CounterBox()
        let viewModel = InternalNotificationDiagnosticsViewModel(
            diagnosticsAPI: MockInternalDiagnosticsAPI(),
            localStateProvider: { PushLifecycleDiagnosticsState(currentDeviceInstallationId: "install-123") },
            reregisterCurrentDevice: {
                counter.value += 1
            }
        )

        await viewModel.reRegisterThisDevice()

        XCTAssertEqual(counter.value, 1)
        XCTAssertFalse(viewModel.isReregisteringDevice)
    }

    func testDiagnosticSummaryIncludesLocalStateAndRecentDelivery() {
        let snapshot = makeSummarySnapshot()
        let viewModel = InternalNotificationDiagnosticsViewModel(
            diagnosticsAPI: MockInternalDiagnosticsAPI(snapshotResult: .success(snapshot)),
            localStateProvider: {
                PushLifecycleDiagnosticsState(
                    currentDeviceInstallationId: "install-123",
                    currentDeviceTokenSuffix: "abcdef",
                    lastDeviceRegistrationResult: .success,
                    currentDevicePresenceIsForeground: true
                )
            },
            reregisterCurrentDevice: {}
        )
        viewModel.replaceSnapshotForTesting(snapshot)

        let summary = viewModel.diagnosticSummary()

        XCTAssertTrue(summary.contains("user_id: user-123"))
        XCTAssertTrue(summary.contains("current_installation_id: install-123"))
        XCTAssertTrue(summary.contains("last_registration_result: success"))
        XCTAssertTrue(summary.contains("scheduler_last_status: completed"))
        XCTAssertTrue(summary.contains("scheduler_task_reminders_dispatched: 2"))
        XCTAssertTrue(summary.contains("scheduler_run_count: 1"))
        XCTAssertTrue(summary.contains("recent_delivery_count: 1"))
        XCTAssertTrue(summary.contains("recent_scheduler_decision_count: 1"))
        XCTAssertTrue(summary.contains("scheduler_decision[dispatch]: no_reminder_intent"))
        XCTAssertTrue(summary.contains("notification_kind=test_push"))
    }
}

private func makeSummarySnapshot() -> InternalNotificationDiagnosticsSnapshot {
    InternalNotificationDiagnosticsSnapshot(
        canAccessInternalDiagnostics: true,
        accountSummary: NotificationDiagnosticsAccountSummary(userId: "user-123"),
        scheduler: NotificationDiagnosticsSchedulerStatus(
            workerName: "notification_schedule",
            lastStartedAt: "2026-04-20T08:00:00Z",
            lastCompletedAt: "2026-04-20T08:00:01Z",
            lastStatus: "completed",
            lastError: nil,
            lastTaskRemindersDue: 2,
            lastTaskRemindersDispatched: 2,
            lastMorningDigestsDue: 0,
            lastMorningDigestsDispatched: 0
        ),
        schedulerRuns: [
            NotificationDiagnosticsSchedulerRunRow(
                workerName: "notification_schedule",
                startedAt: "2026-04-20T08:00:00Z",
                completedAt: "2026-04-20T08:00:01Z",
                status: "completed",
                error: nil,
                taskRemindersDue: 2,
                taskRemindersDispatched: 2,
                morningDigestsDue: 0,
                morningDigestsDispatched: 0
            )
        ],
        installations: [
            NotificationDiagnosticsInstallationRow(
                installationId: "install-123",
                userId: "user-123",
                platform: "ios",
                tokenSuffix: "abcdef",
                isForeground: true
            )
        ],
        recentDelivery: [
            NotificationDiagnosticsDeliveryAuditRow(
                createdAt: "2026-04-19T10:00:00Z",
                userId: "user-123",
                installationId: "install-123",
                notificationKind: "test_push",
                platform: "ios",
                tokenSuffix: "abcdef",
                deliveryResult: "sent",
                skipReason: nil,
                apnsStatusCode: nil,
                apnsReason: nil,
                apnsTopic: "ai.trysidebar.app",
                apnsEnvironment: "dev"
            )
        ],
        recentSchedulerDecisions: [
            NotificationSchedulerDecisionRow(
                createdAt: "2026-04-20T08:00:00Z",
                runStartedAt: "2026-04-20T08:00:00Z",
                userId: "user-123",
                notificationKind: "task_reminder",
                decisionStage: "dispatch",
                decisionReason: "no_reminder_intent",
                scheduledTime: "09:00",
                scheduleTimezone: "Europe/London",
                localNow: "2026-04-20T09:00:00+01:00",
                detail: "no_due_tasks"
            )
        ]
    )
}

@MainActor
private final class MockInternalDiagnosticsAPI: InternalDiagnosticsProviding {
    var snapshotResult: Result<InternalNotificationDiagnosticsSnapshot, Error>
    var testPushResult: Result<InternalNotificationTestPushResponse, Error>
    private(set) var getSnapshotCallCount = 0
    private(set) var sendTestPushInstallationIds: [String] = []

    init(
        snapshotResult: Result<InternalNotificationDiagnosticsSnapshot, Error> = .failure(SettingsViewModelMockError.forced),
        testPushResult: Result<InternalNotificationTestPushResponse, Error> = .failure(SettingsViewModelMockError.forced)
    ) {
        self.snapshotResult = snapshotResult
        self.testPushResult = testPushResult
    }

    func getSnapshot() async throws -> InternalNotificationDiagnosticsSnapshot {
        getSnapshotCallCount += 1
        return try snapshotResult.get()
    }

    func sendTestPush(installationId: String) async throws -> InternalNotificationTestPushResponse {
        sendTestPushInstallationIds.append(installationId)
        return try testPushResult.get()
    }
}

private final class CounterBox {
    var value = 0
}
