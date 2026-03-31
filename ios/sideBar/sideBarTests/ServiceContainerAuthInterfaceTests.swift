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
}

private final class AuthCapabilitySessionDouble: AuthSession, OfflineAccessRestoring, SignInRateLimitStatusProviding {
    let accessToken: String? = nil
    let userId: String? = nil
    let authState: AuthState = .signedOut
    let pendingVerificationEmail: String? = nil

    let canRestoreOfflineSession: Bool
    let restoreOfflineSessionResult: Bool
    let lockoutRemainingSeconds: Int?
    private(set) var restoreOfflineSessionCallCount = 0

    init(
        canRestoreOfflineSession: Bool,
        restoreOfflineSessionResult: Bool,
        lockoutRemainingSeconds: Int?
    ) {
        self.canRestoreOfflineSession = canRestoreOfflineSession
        self.restoreOfflineSessionResult = restoreOfflineSessionResult
        self.lockoutRemainingSeconds = lockoutRemainingSeconds
    }

    var authorizationToken: String? {
        nil
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
    }

    func refreshSessionIfStale() async {
    }

    func signOut() async {
    }

    func restoreOfflineSession() -> Bool {
        restoreOfflineSessionCallCount += 1
        return restoreOfflineSessionResult
    }
}
