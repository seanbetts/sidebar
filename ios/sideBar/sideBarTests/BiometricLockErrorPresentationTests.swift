import XCTest
import LocalAuthentication
@testable import sideBar

final class BiometricLockErrorPresentationTests: XCTestCase {
    func testUnavailableBiometryOffersPasscodeFallback() {
        let state = BiometricLockErrorPresentation.unavailableState(
            for: .biometryNotAvailable,
            biometryName: "Face ID"
        )

        XCTAssertEqual(state.message, "Face ID is not available on this device.")
        XCTAssertTrue(state.showsPasscodeFallback)
    }

    func testNotEnrolledBiometryOffersPasscodeFallback() {
        let state = BiometricLockErrorPresentation.unavailableState(
            for: .biometryNotEnrolled,
            biometryName: "Touch ID"
        )

        XCTAssertEqual(state.message, "Touch ID is not set up. Enable it in Settings.")
        XCTAssertTrue(state.showsPasscodeFallback)
    }

    func testPasscodeNotSetDoesNotOfferFallback() {
        let state = BiometricLockErrorPresentation.unavailableState(
            for: .passcodeNotSet,
            biometryName: "Face ID"
        )

        XCTAssertEqual(state.message, "Set a device passcode to use Face ID.")
        XCTAssertFalse(state.showsPasscodeFallback)
    }
}
