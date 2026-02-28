import XCTest
@testable import sideBar

final class LoginEmailPrefillTests: XCTestCase {
    func testUsesStoredEmailWhenCurrentIsBlank() {
        let result = LoginEmailPrefill.initialEmail(
            currentEmail: "",
            storedEmail: "saved@example.com"
        )

        XCTAssertEqual(result, "saved@example.com")
    }

    func testTrimsStoredEmailBeforePrefill() {
        let result = LoginEmailPrefill.initialEmail(
            currentEmail: "  ",
            storedEmail: "  saved@example.com  "
        )

        XCTAssertEqual(result, "saved@example.com")
    }

    func testKeepsCurrentEmailWhenAlreadyPresent() {
        let result = LoginEmailPrefill.initialEmail(
            currentEmail: "typed@example.com",
            storedEmail: "saved@example.com"
        )

        XCTAssertEqual(result, "typed@example.com")
    }
}
