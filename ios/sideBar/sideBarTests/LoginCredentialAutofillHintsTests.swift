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
}
