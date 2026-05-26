import XCTest
@testable import sideBar

@MainActor
final class WorkspaceRestorationCoordinatorTests: XCTestCase {
    func testSaveSnapshotPersistsWhenAuthenticatedAndNotSuppressed() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        var policy = RestorationSaveSuppressionPolicy(
            isApplying: false,
            queuedSaveSuppressions: 0
        )
        let route = PhoneWorkspaceRoute(section: .notes, detail: .note(id: "note-1"))
        let updatedAt = Date(timeIntervalSince1970: 1_000)

        let didSave = harness.coordinator.saveSnapshot(
            request: WorkspaceRestorationSaveRequest(
                isAuthenticated: true,
                family: .phone,
                userId: "user-1",
                phoneRoute: route,
                splitWorkspace: nil,
                updatedAt: updatedAt
            ),
            saveSuppressionPolicy: &policy
        )

        XCTAssertTrue(didSave)
        let snapshot = try XCTUnwrap(harness.store.load(
            family: .phone,
            expectedUserId: "user-1"
        ))
        XCTAssertEqual(snapshot.phoneRoute, route)
        XCTAssertEqual(snapshot.updatedAt, updatedAt)
        XCTAssertEqual(policy.queuedSaveSuppressions, 0)
    }

    func testSaveSnapshotConsumesSuppressionInsteadOfPersisting() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        var policy = RestorationSaveSuppressionPolicy(
            isApplying: false,
            queuedSaveSuppressions: 1
        )

        let didSave = harness.coordinator.saveSnapshot(
            request: WorkspaceRestorationSaveRequest(
                isAuthenticated: true,
                family: .phone,
                userId: "user-1",
                phoneRoute: PhoneWorkspaceRoute(section: .chat, detail: nil),
                splitWorkspace: nil,
                updatedAt: Date(timeIntervalSince1970: 1_000)
            ),
            saveSuppressionPolicy: &policy
        )

        XCTAssertFalse(didSave)
        XCTAssertNil(harness.store.load(family: .phone, expectedUserId: "user-1"))
        XCTAssertEqual(policy.queuedSaveSuppressions, 0)
    }

    func testInitialLaunchUsesDueTodayBeforePersistedSnapshot() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        harness.store.save(workspaceSnapshot(userId: "user-1"))
        var didApplySuppression = false
        var appliedDueTodayDateKey: String?
        var didApplySnapshot = false

        let didApply = await harness.coordinator.applyInitialLaunchDestination(
            request: WorkspaceRestorationInitialLaunchRequest(
                authState: .active,
                isProtectedContentReady: true,
                shouldSkipRestoration: false,
                family: .workspace,
                userId: "user-1",
                todayDateKey: "2026-05-26"
            ),
            loadTodayTaskCount: {
                WorkspaceRestorationTodayCountResult(
                    previousCounts: nil,
                    currentCounts: taskCounts(today: 2, generatedAt: "fresh"),
                    errorMessage: nil
                )
            },
            applyWithSaveSuppression: { operation in
                didApplySuppression = true
                return await operation()
            },
            applyDueToday: { localDateKey in
                appliedDueTodayDateKey = localDateKey
                return true
            },
            applySnapshot: { _ in
                didApplySnapshot = true
                return true
            }
        )

        XCTAssertTrue(didApply)
        XCTAssertTrue(didApplySuppression)
        XCTAssertEqual(appliedDueTodayDateKey, "2026-05-26")
        XCTAssertFalse(didApplySnapshot)
    }

    func testInitialLaunchAppliesStoredSnapshotWhenDueTodayAlreadyOpened() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        let snapshot = workspaceSnapshot(userId: "user-1")
        harness.store.save(snapshot)
        harness.store.recordDueTodayAutoOpen(userId: "user-1", localDateKey: "2026-05-26")
        var appliedSnapshot: DeviceWorkspaceSnapshot?

        let didApply = await harness.coordinator.applyInitialLaunchDestination(
            request: WorkspaceRestorationInitialLaunchRequest(
                authState: .active,
                isProtectedContentReady: true,
                shouldSkipRestoration: false,
                family: .workspace,
                userId: "user-1",
                todayDateKey: "2026-05-26"
            ),
            loadTodayTaskCount: {
                WorkspaceRestorationTodayCountResult(
                    previousCounts: nil,
                    currentCounts: taskCounts(today: 2, generatedAt: "fresh"),
                    errorMessage: nil
                )
            },
            applyWithSaveSuppression: { operation in
                await operation()
            },
            applyDueToday: { _ in
                XCTFail("Due-today launch should not run after the daily marker is recorded")
                return false
            },
            applySnapshot: { snapshot in
                appliedSnapshot = snapshot
                return true
            }
        )

        XCTAssertTrue(didApply)
        XCTAssertEqual(appliedSnapshot, snapshot)
    }

    func testDueTodayLaunchOverrideRecordsMarkerAfterLoadingToday() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        var appliedPlan: DueTodayLaunchOverridePlan?

        let didApply = await harness.coordinator.applyDueTodayLaunchOverride(
            request: WorkspaceRestorationDueTodayRequest(
                userId: "user-1",
                localDateKey: "2026-05-26",
                isPhone: true
            ),
            loadTodayForLaunch: { true },
            applyPlan: { plan in
                appliedPlan = plan
            }
        )

        XCTAssertTrue(didApply)
        XCTAssertEqual(appliedPlan?.sidebarSelection, .tasks)
        XCTAssertEqual(appliedPlan?.layout, .compact)
        XCTAssertTrue(harness.store.hasDueTodayAutoOpened(
            userId: "user-1",
            localDateKey: "2026-05-26"
        ))
    }

    func testRestoredWorkspaceRoutesByDeviceFamily() async throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        let route = PhoneWorkspaceRoute(section: .files, detail: .file(id: "file-1"))
        let snapshot = DeviceWorkspaceSnapshot(
            schemaVersion: DeviceWorkspaceSnapshot.currentSchemaVersion,
            userId: "user-1",
            family: .phone,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            phoneRoute: route,
            splitWorkspace: nil
        )
        var appliedRoute: PhoneWorkspaceRoute?

        let didApply = await harness.coordinator.applyRestoredWorkspace(
            snapshot,
            family: .phone,
            applyPhoneRoute: { route in
                appliedRoute = route
            },
            applySplitWorkspace: { _ in
                XCTFail("Phone restoration should not apply split workspace state")
            }
        )

        XCTAssertTrue(didApply)
        XCTAssertEqual(appliedRoute, route)
    }

    private func makeHarness() throws -> Harness {
        let suiteName = "WorkspaceRestorationCoordinatorTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let store = WorkspaceRestorationStore(userDefaults: defaults)
        return Harness(
            suiteName: suiteName,
            defaults: defaults,
            store: store,
            coordinator: WorkspaceRestorationCoordinator(store: store)
        )
    }

    private func workspaceSnapshot(userId: String?) -> DeviceWorkspaceSnapshot {
        DeviceWorkspaceSnapshot(
            schemaVersion: DeviceWorkspaceSnapshot.currentSchemaVersion,
            userId: userId,
            family: .workspace,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            phoneRoute: nil,
            splitWorkspace: SplitWorkspaceSnapshot(
                sidebarSelection: .notes,
                primaryDescriptor: .builtIn(.notes),
                secondaryDescriptor: .builtIn(.chat),
                focusedPane: .primary,
                isLeftPanelExpanded: true,
                isWorkspaceExpanded: false
            )
        )
    }

    private func taskCounts(today: Int, generatedAt: String) -> TaskCountsResponse {
        TaskCountsResponse(
            generatedAt: generatedAt,
            counts: TaskCounts(today: today, upcoming: 0, completed: 0),
            projects: [],
            groups: []
        )
    }
}

private struct Harness {
    let suiteName: String
    let defaults: UserDefaults
    let store: WorkspaceRestorationStore
    let coordinator: WorkspaceRestorationCoordinator

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
