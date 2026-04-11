import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class AppEnvironmentStaleAuthRetryTests: XCTestCase {
    func testRefreshAuthStateDoesNotShowStaleAuthRetryBannerImmediately() {
        let authSession = StaleRetryAuthSession(authState: .active)
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient()
        )
        let environment = AppEnvironment(
            container: container,
            staleAuthRetryBannerDelayNanoseconds: 50_000_000
        )

        authSession.authState = .stale
        environment.refreshAuthState()

        XCTAssertEqual(environment.authState, .stale)
        XCTAssertFalse(environment.shouldShowStaleAuthRetryBanner)
    }

    func testRefreshAuthStateShowsStaleAuthRetryBannerAfterDelay() async {
        let authSession = StaleRetryAuthSession(authState: .active)
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient()
        )
        let environment = AppEnvironment(
            container: container,
            staleAuthRetryBannerDelayNanoseconds: 50_000_000
        )

        authSession.authState = .stale
        environment.refreshAuthState()

        XCTAssertFalse(environment.shouldShowStaleAuthRetryBanner)

        await waitForStaleAuthRetryBannerToAppear(in: environment)

        XCTAssertTrue(environment.shouldShowStaleAuthRetryBanner)
    }

    func testRefreshAuthStateCancelsDelayedStaleAuthRetryBannerOnRecovery() async {
        let authSession = StaleRetryAuthSession(authState: .active)
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient()
        )
        let environment = AppEnvironment(
            container: container,
            staleAuthRetryBannerDelayNanoseconds: 80_000_000
        )

        authSession.authState = .stale
        environment.refreshAuthState()
        authSession.authState = .active
        environment.refreshAuthState()

        try? await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertEqual(environment.authState, .active)
        XCTAssertFalse(environment.shouldShowStaleAuthRetryBanner)
    }

    func testRefreshAuthStateHidesVisibleStaleAuthRetryBannerOnRecovery() async {
        let authSession = StaleRetryAuthSession(authState: .active)
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient()
        )
        let environment = AppEnvironment(
            container: container,
            staleAuthRetryBannerDelayNanoseconds: 50_000_000
        )

        authSession.authState = .stale
        environment.refreshAuthState()
        await waitForStaleAuthRetryBannerToAppear(in: environment)
        XCTAssertTrue(environment.shouldShowStaleAuthRetryBanner)

        authSession.authState = .active
        environment.refreshAuthState()

        XCTAssertEqual(environment.authState, .active)
        XCTAssertFalse(environment.shouldShowStaleAuthRetryBanner)
    }

    func testBeginSignOutClearsVisibleStaleAuthRetryBanner() async {
        let authSession = StaleRetryAuthSession(authState: .active)
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient()
        )
        let environment = AppEnvironment(
            container: container,
            staleAuthRetryBannerDelayNanoseconds: 50_000_000
        )

        authSession.authState = .stale
        environment.refreshAuthState()
        await waitForStaleAuthRetryBannerToAppear(in: environment)
        XCTAssertTrue(environment.shouldShowStaleAuthRetryBanner)

        await environment.beginSignOut()

        XCTAssertEqual(environment.authState, .signedOut)
        XCTAssertFalse(environment.shouldShowStaleAuthRetryBanner)
    }

    func testRetryStaleAuthSessionRefreshesAndUpdatesAuthState() async {
        let authSession = StaleRetryAuthSession(authState: .stale)
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient()
        )
        let environment = AppEnvironment(
            container: container,
            staleAuthRetryBannerDelayNanoseconds: 50_000_000
        )
        environment.authState = .stale

        await environment.retryStaleAuthSession()

        XCTAssertEqual(authSession.refreshSessionCallCount, 1)
        XCTAssertEqual(environment.authState, .active)
    }

    func testRetryStaleAuthSessionSkipsRefreshWhenSessionIsNotStale() async {
        let authSession = StaleRetryAuthSession(authState: .active)
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient()
        )
        let environment = AppEnvironment(
            container: container,
            staleAuthRetryBannerDelayNanoseconds: 50_000_000
        )
        environment.authState = .active

        await environment.retryStaleAuthSession()

        XCTAssertEqual(authSession.refreshSessionCallCount, 0)
        XCTAssertEqual(environment.authState, .active)
    }

    private func waitForStaleAuthRetryBannerToAppear(
        in environment: AppEnvironment,
        timeoutNanoseconds: UInt64 = 500_000_000,
        pollNanoseconds: UInt64 = 10_000_000
    ) async {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while !environment.shouldShowStaleAuthRetryBanner {
            if DispatchTime.now().uptimeNanoseconds >= deadline {
                XCTFail("Timed out waiting for stale auth retry banner to appear")
                return
            }
            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }
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
