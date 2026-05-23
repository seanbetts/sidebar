import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class AppEnvironmentSyncHealthTests: XCTestCase {
    private var retainedEnvironments: [AppEnvironment] = []

    func testCurrentSyncHealthIsReconnectingWhileReconnectRefreshIsPending() async throws {
        let refreshCoordinator = BlockingRefreshCoordinator()
        let environment = makeEnvironment(refreshCoordinator: refreshCoordinator)
        try await requireProtectedServerReadsAllowed(in: environment)

        let refreshTask = Task { @MainActor in
            await environment.syncCoordinator.refreshAll()
        }

        await refreshCoordinator.waitForRefreshStart()

        try await requireProtectedServerReadsAllowed(in: environment)
        XCTAssertEqual(environment.currentSyncHealth, .reconnecting)

        refreshCoordinator.finishRefresh()
        await refreshTask.value
        try await requireProtectedServerReadsAllowed(in: environment)
        XCTAssertEqual(environment.currentSyncHealth, .degraded)
    }

    private func makeEnvironment(refreshCoordinator: RefreshCoordinatorType) -> AppEnvironment {
        let authSession = SyncHealthMutableAuthSession(
            accessToken: "access-token",
            userId: "user-1",
            authState: .active
        )
        let container = makeNoNetworkServiceContainer(
            authSession: authSession,
            cacheClient: InMemoryCacheClient()
        )
        let environment = AppEnvironment(container: container, refreshCoordinator: refreshCoordinator)
        retainedEnvironments.append(environment)
        return environment
    }

    private func requireProtectedServerReadsAllowed(
        in environment: AppEnvironment,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        (environment.container.authSession as? SyncHealthMutableAuthSession)?.restoreActiveSession()
        environment.authState = .active
        for _ in 0..<2 {
            NotificationCenter.default.post(name: .apiClientRequestSucceeded, object: nil)
        }
        for _ in 0..<20 where !canAttemptProtectedServerRead(in: environment) {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        guard canAttemptProtectedServerRead(in: environment) else {
            XCTFail("Protected server-read precondition could not be established", file: file, line: line)
            throw TestPreconditionFailure()
        }
    }

    private func canAttemptProtectedServerRead(in environment: AppEnvironment) -> Bool {
        environment.connectivityMonitor.canAttemptServerRead
            && environment.protectedContentReadiness.canAttemptServerRead
    }
}

private struct TestPreconditionFailure: Error {}

private final class SyncHealthMutableAuthSession:
    AuthSession,
    AuthSessionInvalidating,
    AuthSessionTokenScopedInvalidating {

    var accessToken: String?
    var userId: String?
    var authState: AuthState

    var authorizationToken: String? {
        authState == .active ? accessToken : nil
    }

    var pendingVerificationEmail: String? {
        nil
    }

    init(accessToken: String?, userId: String?, authState: AuthState) {
        self.accessToken = accessToken
        self.userId = userId
        self.authState = authState
    }

    func signIn(email: String, password: String) async throws {
        _ = email
        _ = password
        restoreActiveSession()
    }

    func signUp(email: String, password: String) async throws {
        _ = email
        _ = password
    }

    func verifyOTP(email: String, code: String) async throws {
        _ = email
        _ = code
    }

    func refreshSession() async {
        restoreActiveSession()
    }

    func refreshSessionIfStale() async {
    }

    func signOut() async {
        accessToken = nil
        userId = nil
        authState = .signedOut
    }

    func markSessionReauthenticationRequiredAfterAuthorizationFailure() {
        authState = .reauthenticationRequired
    }

    func markSessionReauthenticationRequiredAfterAuthorizationFailure(rejectedToken: String?) {
        if let rejectedToken,
           let accessToken,
           rejectedToken != accessToken {
            return
        }
        markSessionReauthenticationRequiredAfterAuthorizationFailure()
    }

    func restoreActiveSession() {
        accessToken = "access-token"
        userId = "user-1"
        authState = .active
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
