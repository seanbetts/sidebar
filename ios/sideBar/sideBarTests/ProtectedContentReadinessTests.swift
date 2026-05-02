import XCTest
@testable import sideBar

final class ProtectedContentReadinessTests: XCTestCase {
    func testActiveSessionWithoutAuthorizationTokenCannotAttemptProtectedServerReads() {
        let readiness = ProtectedContentReadiness(
            authState: .active,
            hasAuthorizationToken: false,
            isBiometricUnlockEnabled: false,
            isBiometricUnlocked: false
        )

        XCTAssertTrue(readiness.isAuthenticated)
        XCTAssertFalse(readiness.canAttemptServerRead)
        XCTAssertTrue(readiness.canShowProtectedContent)
        XCTAssertFalse(readiness.requiresBiometricUnlock)
    }

    func testBiometricLockBlocksProtectedContentDisplayWithoutBlockingServerReadiness() {
        let readiness = ProtectedContentReadiness(
            authState: .active,
            hasAuthorizationToken: true,
            isBiometricUnlockEnabled: true,
            isBiometricUnlocked: false
        )

        XCTAssertTrue(readiness.isAuthenticated)
        XCTAssertTrue(readiness.canAttemptServerRead)
        XCTAssertFalse(readiness.canShowProtectedContent)
        XCTAssertTrue(readiness.requiresBiometricUnlock)
    }

    func testReauthenticationRequiredBlocksServerReadsAndProtectedContent() {
        let readiness = ProtectedContentReadiness(
            authState: .reauthenticationRequired,
            hasAuthorizationToken: true,
            isBiometricUnlockEnabled: false,
            isBiometricUnlocked: true
        )

        XCTAssertFalse(readiness.isAuthenticated)
        XCTAssertFalse(readiness.canAttemptServerRead)
        XCTAssertFalse(readiness.canShowProtectedContent)
        XCTAssertFalse(readiness.requiresBiometricUnlock)
    }
}
