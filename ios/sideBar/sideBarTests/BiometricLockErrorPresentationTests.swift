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
        XCTAssertTrue(state.showsSettingsAction)
    }

    func testNotEnrolledBiometryOffersPasscodeFallback() {
        let state = BiometricLockErrorPresentation.unavailableState(
            for: .biometryNotEnrolled,
            biometryName: "Touch ID"
        )

        XCTAssertEqual(state.message, "Touch ID is not set up. Enable it in Settings.")
        XCTAssertTrue(state.showsPasscodeFallback)
        XCTAssertTrue(state.showsSettingsAction)
    }

    func testPasscodeNotSetOffersSettingsActionWithoutPasscodeFallback() {
        let state = BiometricLockErrorPresentation.unavailableState(
            for: .passcodeNotSet,
            biometryName: "Face ID"
        )

        XCTAssertEqual(state.message, "Set a device passcode to use Face ID.")
        XCTAssertFalse(state.showsPasscodeFallback)
        XCTAssertTrue(state.showsSettingsAction)
    }

    func testDefaultUnavailableStateDoesNotOfferSettingsAction() {
        let state = BiometricLockErrorPresentation.unavailableState(
            for: nil,
            biometryName: "Biometric Unlock"
        )

        XCTAssertEqual(state.message, "Biometric authentication is unavailable.")
        XCTAssertFalse(state.showsPasscodeFallback)
        XCTAssertFalse(state.showsSettingsAction)
    }
}
