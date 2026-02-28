import XCTest
@testable import sideBar

final class LoginCredentialAutofillHintsTests: XCTestCase {
    func testEmailUsesEmailAddressHint() {
        XCTAssertEqual(
            LoginCredentialAutofillHints.emailIdentifier,
            PlatformTextContentType.emailAddress.rawValue
        )
    }

    func testPasswordUsesPasswordHint() {
        XCTAssertEqual(
            LoginCredentialAutofillHints.passwordIdentifier,
            PlatformTextContentType.password.rawValue
        )
    }
}
