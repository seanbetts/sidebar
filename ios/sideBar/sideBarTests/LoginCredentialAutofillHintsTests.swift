import XCTest
@testable import sideBar

final class LoginCredentialAutofillHintsTests: XCTestCase {
    func testEmailUsesUsernameHint() {
        XCTAssertEqual(
            LoginCredentialAutofillHints.emailIdentifier,
            PlatformTextContentType.username.rawValue
        )
    }

    func testPasswordUsesPasswordHint() {
        XCTAssertEqual(
            LoginCredentialAutofillHints.passwordIdentifier,
            PlatformTextContentType.password.rawValue
        )
    }

    func testEmailAutofocusAllowedWhenOnboardingIsHidden() {
        XCTAssertTrue(LoginFocusPolicy.shouldAutofocusEmail(isOnboardingPresented: false))
    }

    func testEmailAutofocusSuppressedWhenOnboardingIsShowing() {
        XCTAssertFalse(LoginFocusPolicy.shouldAutofocusEmail(isOnboardingPresented: true))
    }
}
