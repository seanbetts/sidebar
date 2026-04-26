import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class AppEnvironmentStaleAuthRetryTests: XCTestCase {
    func testRecoverableStaleAuthKeepsProtectedContentReadyWhenBiometricUnlocked() {
        let authSession = StaleRetryAuthSession(authState: .active)
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient()
        )
        let environment = AppEnvironment(
            container: container,
            refreshCoordinator: NoopRefreshCoordinator()
        )

        authSession.authState = .staleRecoverable
        environment.refreshAuthState()

        XCTAssertEqual(environment.authState, .staleRecoverable)
        XCTAssertTrue(environment.isAuthenticated)
        XCTAssertTrue(environment.isProtectedContentReady)
    }

    func testRecoverableStaleAuthRefreshesAutomaticallyOnActivation() async {
        let authSession = StaleRetryAuthSession(authState: .active)
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient()
        )
        let environment = AppEnvironment(
            container: container,
            refreshCoordinator: NoopRefreshCoordinator()
        )

        authSession.authState = .staleRecoverable
        environment.refreshAuthState()

        await environment.handleSignedInActivation(includeDeferredRefresh: false)

        XCTAssertEqual(authSession.refreshSessionCallCount, 1)
        XCTAssertEqual(environment.authState, .active)
    }

    func testRecoverableStaleAuthRefreshesBeforeContentActivation() async {
        let authSession = StaleRetryAuthSession(authState: .staleRecoverable)
        let refreshCoordinator = RecordingRefreshCoordinator(observedAuthState: { authSession.authState })
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient()
        )
        let environment = AppEnvironment(
            container: container,
            refreshCoordinator: refreshCoordinator
        )

        await environment.handleSignedInActivation(includeDeferredRefresh: true)

        XCTAssertGreaterThanOrEqual(authSession.refreshSessionCallCount, 1)
        XCTAssertEqual(refreshCoordinator.activationAuthStates, [.active])
    }

    func testRefreshAuthStateSchedulesRecoverableStaleAuthActivation() async {
        let authSession = StaleRetryAuthSession(authState: .signedOut)
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient()
        )
        let environment = AppEnvironment(
            container: container,
            refreshCoordinator: NoopRefreshCoordinator()
        )

        authSession.accessToken = "stale-token"
        authSession.userId = "user-id"
        authSession.authState = .staleRecoverable
        environment.refreshAuthState()

        await waitUntil(timeoutSeconds: 1.0) {
            authSession.refreshSessionCallCount == 1
        }
        XCTAssertEqual(environment.authState, .active)
    }

    func testBeginSignOutClearsRecoverableStaleAuth() async {
        let authSession = StaleRetryAuthSession(authState: .active)
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient()
        )
        let environment = AppEnvironment(container: container)

        authSession.authState = .staleRecoverable
        environment.refreshAuthState()

        await environment.beginSignOut()

        XCTAssertEqual(environment.authState, .signedOut)
    }

}

private final class StaleRetryAuthSession: AuthSession {
    var accessToken: String? = "token"
    var userId: String? = "user-id"
    var authState: AuthState

    var authorizationToken: String? {
        authState == .active ? accessToken : nil
    }

    var pendingVerificationEmail: String? {
        nil
    }

    private(set) var refreshSessionCallCount = 0

    init(authState: AuthState) {
        self.authState = authState
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

    func refresh(trigger: RefreshTrigger, context: RefreshContext) async {
        _ = trigger
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

    func refresh(trigger: RefreshTrigger, context: RefreshContext) async {
        _ = trigger
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
