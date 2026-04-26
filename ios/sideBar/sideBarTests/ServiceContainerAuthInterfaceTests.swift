import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class ServiceContainerAuthInterfaceTests: XCTestCase {
    func testContainerExposesOfflineRestoreCapabilityThroughProductInterface() {
        let authSession = AuthCapabilitySessionDouble(
            canRestoreOfflineSession: true,
            restoreOfflineSessionResult: true,
            lockoutRemainingSeconds: 45
        )
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient()
        )

        XCTAssertTrue(container.offlineAccessRestorer?.canRestoreOfflineSession == true)
        XCTAssertTrue(container.offlineAccessRestorer?.restoreOfflineSession() == true)
        XCTAssertEqual(authSession.restoreOfflineSessionCallCount, 1)
    }

    func testContainerExposesSignInRateLimitCapabilityThroughProductInterface() {
        let authSession = AuthCapabilitySessionDouble(
            canRestoreOfflineSession: false,
            restoreOfflineSessionResult: false,
            lockoutRemainingSeconds: 45
        )
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient()
        )

        XCTAssertEqual(container.signInRateLimiter?.lockoutRemainingSeconds, 45)
    }

    func testMakeRealtimeClientReturnsPlaceholderUnderXCTest() {
        let authSession = AuthCapabilitySessionDouble(
            canRestoreOfflineSession: false,
            restoreOfflineSessionResult: false,
            lockoutRemainingSeconds: nil
        )
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient()
        )

        XCTAssertTrue(container.makeRealtimeClient(handler: nil) is PlaceholderRealtimeClient)
    }

    func testAPIClientRefreshHookRequiresTokenChangeAndMarksRejectedAuthStale() async {
        let authSession = AuthCapabilitySessionDouble(
            canRestoreOfflineSession: false,
            restoreOfflineSessionResult: false,
            lockoutRemainingSeconds: nil,
            authorizationToken: "token-1"
        )
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: authSession,
            cacheClient: InMemoryCacheClient()
        )

        let refreshed = await container.apiClient.config.refreshAuthIfNeeded?()
        await container.apiClient.config.handleAuthRejected?()

        XCTAssertEqual(refreshed, false)
        XCTAssertEqual(authSession.refreshSessionCallCount, 1)
        XCTAssertEqual(authSession.markSessionStaleAfterAuthorizationFailureCallCount, 1)
    }
}

private final class AuthCapabilitySessionDouble: AuthSession, OfflineAccessRestoring, SignInRateLimitStatusProviding,
    AuthSessionInvalidating {
    let accessToken: String? = nil
    let userId: String? = nil
    let authState: AuthState = .signedOut
    let pendingVerificationEmail: String? = nil

    let canRestoreOfflineSession: Bool
    let restoreOfflineSessionResult: Bool
    let lockoutRemainingSeconds: Int?
    private let token: String?
    private(set) var restoreOfflineSessionCallCount = 0
    private(set) var refreshSessionCallCount = 0
    private(set) var markSessionStaleAfterAuthorizationFailureCallCount = 0

    init(
        canRestoreOfflineSession: Bool,
        restoreOfflineSessionResult: Bool,
        lockoutRemainingSeconds: Int?,
        authorizationToken: String? = nil
    ) {
        self.canRestoreOfflineSession = canRestoreOfflineSession
        self.restoreOfflineSessionResult = restoreOfflineSessionResult
        self.lockoutRemainingSeconds = lockoutRemainingSeconds
        token = authorizationToken
    }

    var authorizationToken: String? {
        token
    }

    func signIn(email: String, password: String) async throws {
        _ = email
        _ = password
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
    }

    func refreshSessionIfStale() async {
    }

    func signOut() async {
    }

    func restoreOfflineSession() -> Bool {
        restoreOfflineSessionCallCount += 1
        return restoreOfflineSessionResult
    }

    func markSessionStaleAfterAuthorizationFailure() {
        markSessionStaleAfterAuthorizationFailureCallCount += 1
    }
}
