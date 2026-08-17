import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class AppEnvironmentStaleAuthRetryTests: XCTestCase {
    private var retainedEnvironments: [AppEnvironment] = []
    private var isolatedDefaults: TestIsolation.IsolatedUserDefaults!

    override func setUp() {
        super.setUp()
        retainedEnvironments.removeAll()
        isolatedDefaults = TestIsolation.makeUserDefaults(
            prefix: "AppEnvironmentStaleAuthRetryTests"
        )
    }

    override func tearDown() {
        retainedEnvironments.removeAll()
        isolatedDefaults?.tearDown()
        isolatedDefaults = nil
        super.tearDown()
    }

    func testRecoverableStaleAuthKeepsProtectedContentReadyWhenBiometricUnlocked() {
        let authSession = StaleRetryAuthSession(authState: .active)
        let container = makeContainer(authSession: authSession)
        let environment = AppEnvironment(
            container: container,
            storage: isolatedStorage(),
            refreshCoordinator: NoopRefreshCoordinator()
        )
        retainedEnvironments.append(environment)

        authSession.authState = .staleRecoverable
        environment.refreshAuthState()

        XCTAssertEqual(environment.authState, .staleRecoverable)
        XCTAssertTrue(environment.isAuthenticated)
        XCTAssertTrue(environment.isProtectedContentReady)
    }

    func testRecoverableStaleAuthRefreshesAutomaticallyOnActivation() async {
        let authSession = StaleRetryAuthSession(authState: .active)
        let container = makeContainer(authSession: authSession)
        let environment = AppEnvironment(
            container: container,
            storage: isolatedStorage(),
            refreshCoordinator: NoopRefreshCoordinator()
        )
        retainedEnvironments.append(environment)

        authSession.authState = .staleRecoverable
        environment.refreshAuthState()

        await environment.handleSignedInActivation(includeDeferredRefresh: false)

        XCTAssertEqual(authSession.refreshSessionCallCount, 1)
        XCTAssertEqual(environment.authState, .active)
    }

    func testRecoverableStaleAuthRefreshesBeforeContentActivation() async {
        let authSession = StaleRetryAuthSession(authState: .staleRecoverable)
        let refreshCoordinator = RecordingRefreshCoordinator(observedAuthState: { authSession.authState })
        let container = makeContainer(authSession: authSession)
        let environment = AppEnvironment(
            container: container,
            storage: isolatedStorage(),
            refreshCoordinator: refreshCoordinator
        )
        retainedEnvironments.append(environment)

        await environment.handleSignedInActivation(includeDeferredRefresh: true)

        XCTAssertGreaterThanOrEqual(authSession.refreshSessionCallCount, 1)
        XCTAssertEqual(refreshCoordinator.activationAuthStates, [.active])
    }

    func testRefreshAuthStateSchedulesRecoverableStaleAuthActivation() async {
        let authSession = StaleRetryAuthSession(authState: .signedOut)
        let container = makeContainer(authSession: authSession)
        let environment = AppEnvironment(
            container: container,
            storage: isolatedStorage(),
            refreshCoordinator: NoopRefreshCoordinator()
        )
        retainedEnvironments.append(environment)

        authSession.accessToken = "stale-token"
        authSession.userId = "user-id"
        authSession.authState = .staleRecoverable
        environment.refreshAuthState()

        await waitUntil(timeoutSeconds: 1.0) {
            authSession.refreshSessionCallCount == 1
        }
        XCTAssertEqual(environment.authState, .active)
    }

    func testSameAccountStaleAuthRecoveryReplaysRetainedNotificationWriteBeforeRefresh() async throws {
        let accountId = UUID()
        let task = TaskItem(
            id: UUID().uuidString,
            title: "Recover after stale auth",
            status: "open",
            deadline: TasksUtils.formatDateKey(Date())
        )
        let authorizationToken = try makeUnsignedJWT(subject: accountId.uuidString)
        let authSession = StaleRetryAuthSession(
            authState: .staleRecoverable,
            accessToken: authorizationToken,
            userId: accountId.uuidString
        )
        let tasksAPI = StaleRecoveryTasksAPI(task: task)
        isolatedDefaults.defaults.set(
            accountId.uuidString.lowercased(), forKey: AppStorageKeys.cacheScopeUserId
        )
        let storage = isolatedStorage()
        let container = makeContainer(authSession: authSession, tasksAPI: tasksAPI)
        let environment = AppEnvironment(
            container: container,
            storage: storage,
            refreshCoordinator: NoopRefreshCoordinator()
        )
        retainedEnvironments.append(environment)
        let accountScope = try XCTUnwrap(environment.taskNotificationAuthContext?.accountScope)
        environment.tasksStore.tasks = [task]
        environment.tasksStore.counts = TaskCountsResponse(
            generatedAt: nil,
            counts: TaskCounts(today: 1, upcoming: 0, completed: 0),
            projects: [],
            groups: []
        )
        storage.widgetDataManager.storeTaskData(
            WidgetTaskData(
                tasks: [WidgetTask(id: task.id, title: task.title)],
                totalCount: 1,
                progressCompletedCount: 0,
                progressTotalCount: 1
            ),
            for: .today
        )

        let completionResult = await environment.tasksViewModel
            .completeDueTodayTaskFromNotification(
                taskId: task.id,
                accountScope: accountScope
            )
        await waitUntil(timeoutSeconds: 1) {
            environment.writeQueue.pendingCount == 1
                && !environment.writeQueue.isProcessing
        }

        XCTAssertEqual(completionResult, .queued)
        XCTAssertTrue(environment.connectivityMonitor.offlineCapabilityPolicy.canAttemptServerWrite)
        XCTAssertEqual(tasksAPI.fixedAuthorizationSyncCallCount, 0)
        XCTAssertEqual(tasksAPI.currentSessionSyncCallCount, 0)
        XCTAssertEqual(environment.writeQueue.pendingCount, 1)
        XCTAssertTrue(environment.tasksStore.tasks.isEmpty)
        XCTAssertEqual(environment.tasksStore.counts?.counts.today, 0)
        let retainedSnapshot = storage.widgetDataManager.loadTaskData(for: .today)
        XCTAssertEqual(retainedSnapshot.totalCount, 0)
        XCTAssertEqual(retainedSnapshot.progressCompletedCount, 1)
        XCTAssertEqual(retainedSnapshot.pendingOptimisticCompletionTaskIds, [task.id])

        await environment.handleSignedInActivation(includeDeferredRefresh: true)
        await environment.handleSignedInActivation(includeDeferredRefresh: false)

        XCTAssertEqual(environment.authState, .active)
        XCTAssertEqual(tasksAPI.fixedAuthorizationSyncCallCount, 1)
        XCTAssertEqual(tasksAPI.currentSessionSyncCallCount, 0)
        XCTAssertEqual(tasksAPI.authorizationTokens, [authorizationToken])
        XCTAssertEqual(environment.writeQueue.pendingCount, 0)
        let remainingWrites = try await environment.writeQueue.fetchPendingWrites()
        XCTAssertTrue(remainingWrites.isEmpty)
        XCTAssertTrue(environment.tasksStore.tasks.isEmpty)
        XCTAssertEqual(environment.tasksStore.counts?.counts.today, 0)
        let reconciledSnapshot = storage.widgetDataManager.loadTaskData(for: .today)
        XCTAssertTrue(reconciledSnapshot.tasks.isEmpty)
        XCTAssertEqual(reconciledSnapshot.totalCount, 0)
        XCTAssertEqual(reconciledSnapshot.progressCompletedCount, 1)
        XCTAssertEqual(reconciledSnapshot.progressTotalCount, 1)
        XCTAssertEqual(reconciledSnapshot.optimisticallyCompletedTaskIds, [task.id])
        XCTAssertTrue(reconciledSnapshot.pendingOptimisticCompletionTaskIds.isEmpty)
    }

    func testBeginSignOutClearsRecoverableStaleAuth() async {
        let authSession = StaleRetryAuthSession(authState: .active)
        let container = makeContainer(authSession: authSession)
        let environment = AppEnvironment(container: container, storage: isolatedStorage())
        retainedEnvironments.append(environment)

        authSession.authState = .staleRecoverable
        environment.refreshAuthState()

        await environment.beginSignOut()

        XCTAssertEqual(environment.authState, .signedOut)
    }

    private func isolatedStorage() -> AppEnvironmentStorage {
        AppEnvironmentStorage(userDefaults: isolatedDefaults.defaults)
    }

    private func makeContainer(
        authSession: AuthSession,
        tasksAPI: (any TasksProviding)? = nil
    ) -> ServiceContainer {
        makeNoNetworkServiceContainer(
            authSession: authSession,
            cacheClient: InMemoryCacheClient(),
            tasksAPI: tasksAPI
        )
    }

    private func makeUnsignedJWT(subject: String) throws -> String {
        let headerData = try JSONSerialization.data(
            withJSONObject: ["alg": "none", "typ": "JWT"]
        )
        let payloadData = try JSONSerialization.data(
            withJSONObject: ["sub": subject]
        )
        func encode(_ data: Data) -> String {
            data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return "\(encode(headerData)).\(encode(payloadData))."
    }

}

private final class StaleRetryAuthSession: AuthSession {
    var accessToken: String?
    var userId: String?
    var authState: AuthState

    var authorizationToken: String? {
        authState == .active ? accessToken : nil
    }

    var pendingVerificationEmail: String? {
        nil
    }

    private(set) var refreshSessionCallCount = 0

    init(
        authState: AuthState,
        accessToken: String? = "token",
        userId: String? = "user-id"
    ) {
        self.authState = authState
        self.accessToken = accessToken
        self.userId = userId
    }

    func signIn(email: String, password: String) async throws {
        _ = email
        _ = password
        authState = .active
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
        refreshSessionCallCount += 1
        authState = .active
    }

    func refreshSessionIfStale() async {
    }

    func signOut() async {
        accessToken = nil
        userId = nil
        authState = .signedOut
    }
}

private final class NoopRefreshCoordinator: RefreshCoordinatorType {
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
}

private final class RecordingRefreshCoordinator: RefreshCoordinatorType {
    private let observedAuthState: () -> AuthState
    private(set) var activationAuthStates: [AuthState] = []

    init(observedAuthState: @escaping () -> AuthState) {
        self.observedAuthState = observedAuthState
    }

    func handleActivation(_ request: ActivationRefreshRequest) async {
        _ = request
        activationAuthStates.append(observedAuthState())
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
}

private func waitUntil(
    timeoutSeconds: TimeInterval,
    condition: @escaping () -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while Date() < deadline {
        if condition() {
            return
        }
        await Task.yield()
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}
