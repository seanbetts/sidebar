import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class AppEnvironmentSyncHealthTests: XCTestCase {
    private var retainedEnvironments: [AppEnvironment] = []

    func testCurrentSyncHealthIsReconnectingWhileReconnectRefreshIsPending() async {
        let refreshCoordinator = BlockingRefreshCoordinator()
        let environment = makeEnvironment(refreshCoordinator: refreshCoordinator)
        let refreshTask = Task { @MainActor in
            await environment.syncCoordinator.refreshAll()
        }

        await refreshCoordinator.waitForRefreshStart()

        XCTAssertEqual(environment.currentSyncHealth, .reconnecting)

        refreshCoordinator.finishRefresh()
        await refreshTask.value
        XCTAssertEqual(environment.currentSyncHealth, .degraded)
    }

    private func makeEnvironment(refreshCoordinator: RefreshCoordinatorType) -> AppEnvironment {
        let authSession = PlaceholderAuthSession(
            accessToken: "access-token",
            userId: "user-1",
            authState: .active
        )
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient()
        )
        let environment = AppEnvironment(container: container, refreshCoordinator: refreshCoordinator)
        retainedEnvironments.append(environment)
        return environment
    }
}

@MainActor
private final class BlockingRefreshCoordinator: RefreshCoordinatorType {
    private var refreshStartedContinuation: CheckedContinuation<Void, Never>?
    private var finishContinuation: CheckedContinuation<Void, Never>?
    private var didStartRefresh = false

    func handleActivation(_ request: ActivationRefreshRequest) async {
        _ = request
    }

    func prepareVisibleSectionForPresentation(_ section: AppSection?, canAttemptServerRead: Bool) async {
        _ = section
        _ = canAttemptServerRead
    }

    func hasVisibleDetail(for section: AppSection?) -> Bool {
        _ = section
        return false
    }

    func pinnedSections() -> [AppSection] {
        []
    }

    func refresh(trigger: RefreshTrigger, context: RefreshContext) async {
        _ = trigger
        _ = context
        didStartRefresh = true
        refreshStartedContinuation?.resume()
        refreshStartedContinuation = nil
        await withCheckedContinuation { continuation in
            finishContinuation = continuation
        }
    }

    func scheduleRealtimeInvalidation(_ change: DomainSyncChange, context: RefreshContext) async {
        _ = change
        _ = context
    }

    func scheduleDecodeFailureRefresh(section: AppSection, context: RefreshContext) async {
        _ = section
        _ = context
    }

    func scheduleJobTerminalRefresh(_ change: DomainSyncChange, context: RefreshContext) async {
        _ = change
        _ = context
    }

    func visibleSectionDidChange(to section: AppSection?, context: RefreshContext) async {
        _ = section
        _ = context
    }

    func waitForRefreshStart() async {
        if didStartRefresh {
            return
        }
        await withCheckedContinuation { continuation in
            refreshStartedContinuation = continuation
        }
    }

    func finishRefresh() {
        finishContinuation?.resume()
        finishContinuation = nil
    }
}
