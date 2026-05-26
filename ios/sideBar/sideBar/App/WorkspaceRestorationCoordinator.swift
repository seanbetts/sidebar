import Foundation
import sideBarShared

struct WorkspaceRestorationSaveRequest: Equatable {
    var isAuthenticated: Bool
    var family: DeviceWorkspaceFamily
    var userId: String?
    var phoneRoute: PhoneWorkspaceRoute?
    var splitWorkspace: SplitWorkspaceSnapshot?
    var updatedAt: Date
}

struct WorkspaceRestorationTodayCountResult: Equatable {
    var previousCounts: TaskCountsResponse?
    var currentCounts: TaskCountsResponse?
    var errorMessage: String?
}

struct WorkspaceRestorationInitialLaunchRequest: Equatable {
    var authState: AuthState
    var isProtectedContentReady: Bool
    var shouldSkipRestoration: Bool
    var family: DeviceWorkspaceFamily
    var userId: String?
    var todayDateKey: String
}

struct WorkspaceRestorationDueTodayRequest: Equatable {
    var userId: String?
    var localDateKey: String
    var isPhone: Bool
}

@MainActor
final class WorkspaceRestorationCoordinator {
    private let store: WorkspaceRestorationStore

    init(store: WorkspaceRestorationStore) {
        self.store = store
    }

    @discardableResult
    func saveSnapshot(
        request: WorkspaceRestorationSaveRequest,
        saveSuppressionPolicy: inout RestorationSaveSuppressionPolicy
    ) -> Bool {
        guard !saveSuppressionPolicy.shouldSuppressSave() else {
            return false
        }
        guard request.isAuthenticated else { return false }

        let snapshot = WorkspaceRestorationPlanner.makeDeviceSnapshot(
            family: request.family,
            userId: request.userId,
            phoneRoute: request.family == .phone ? request.phoneRoute : nil,
            splitWorkspace: request.family == .workspace ? request.splitWorkspace : nil,
            updatedAt: request.updatedAt
        )
        store.save(snapshot)
        return true
    }

    func applyInitialLaunchDestination(
        request: WorkspaceRestorationInitialLaunchRequest,
        loadTodayTaskCount: () async -> WorkspaceRestorationTodayCountResult,
        applyWithSaveSuppression: (_ operation: @escaping @MainActor () async -> Bool) async -> Bool,
        applyDueToday: @escaping (_ localDateKey: String) async -> Bool,
        applySnapshot: @escaping (_ snapshot: DeviceWorkspaceSnapshot) async -> Bool
    ) async -> Bool {
        guard request.authState == .active else { return false }
        guard request.isProtectedContentReady else { return false }
        guard !request.shouldSkipRestoration else { return false }

        let snapshot = store.load(
            family: request.family,
            expectedUserId: request.userId
        )
        let countResult = await loadTodayTaskCount()
        let todayTaskCount = WorkspaceRestorationPlanner.freshTodayTaskCountForLaunch(
            previousCounts: countResult.previousCounts,
            currentCounts: countResult.currentCounts,
            errorMessage: countResult.errorMessage
        )
        let destination = WorkspaceRestorationPlanner.makeInitialLaunchDestination(
            hasExternalIntent: false,
            todayTaskCount: todayTaskCount,
            hasOpenedDueToday: store.hasDueTodayAutoOpened(
                userId: request.userId,
                localDateKey: request.todayDateKey
            ),
            hasRestorationSnapshot: snapshot != nil
        )

        switch destination {
        case .externalIntent, .fallbackChat:
            return false
        case .dueTodayTasks:
            return await applyWithSaveSuppression {
                await applyDueToday(request.todayDateKey)
            }
        case .restoredSnapshot:
            guard let snapshot else { return false }
            return await applyWithSaveSuppression {
                await applySnapshot(snapshot)
            }
        }
    }

    func applyDueTodayLaunchOverride(
        request: WorkspaceRestorationDueTodayRequest,
        loadTodayForLaunch: () async -> Bool,
        applyPlan: (DueTodayLaunchOverridePlan) -> Void
    ) async -> Bool {
        guard await loadTodayForLaunch() else {
            return false
        }
        store.recordDueTodayAutoOpen(
            userId: request.userId,
            localDateKey: request.localDateKey
        )
        applyPlan(WorkspaceRestorationPlanner.makeDueTodayLaunchOverridePlan(
            isPhone: request.isPhone
        ))
        return true
    }

    func applyRestoredWorkspace(
        _ snapshot: DeviceWorkspaceSnapshot,
        family: DeviceWorkspaceFamily,
        applyPhoneRoute: (PhoneWorkspaceRoute) async -> Void,
        applySplitWorkspace: (SplitWorkspaceSnapshot) -> Void
    ) async -> Bool {
        switch family {
        case .phone:
            guard let route = snapshot.phoneRoute else { return false }
            await applyPhoneRoute(route)
            return true
        case .workspace:
            guard let splitWorkspace = snapshot.splitWorkspace else { return false }
            applySplitWorkspace(splitWorkspace)
            return true
        }
    }
}
