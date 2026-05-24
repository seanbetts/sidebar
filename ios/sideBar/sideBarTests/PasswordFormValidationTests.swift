import XCTest
@testable import sideBar

@MainActor
final class PasswordFormValidationTests: XCTestCase {
    func testExactPasswordsWithSurroundingWhitespaceCanSubmit() {
        let validation = PasswordFormValidation(
            newPassword: "  StrongPass123!  ",
            confirmPassword: "  StrongPass123!  "
        )

        XCTAssertTrue(validation.hasMinimumPasswordLength)
        XCTAssertNil(validation.passwordMismatchMessage)
        XCTAssertTrue(validation.canSubmit(isSubmitting: false))
        XCTAssertGreaterThan(validation.strengthScore, 0)
    }

    func testMismatchComparesExactPasswordStrings() {
        let validation = PasswordFormValidation(
            newPassword: "  StrongPass123!  ",
            confirmPassword: "StrongPass123!"
        )

        XCTAssertEqual(validation.passwordMismatchMessage, "Passwords don't match.")
        XCTAssertFalse(validation.canSubmit(isSubmitting: false))
    }

    func testSubmittingIsBlockedWhileAlreadySubmitting() {
        let validation = PasswordFormValidation(
            newPassword: "StrongPass123!",
            confirmPassword: "StrongPass123!"
        )

        XCTAssertFalse(validation.canSubmit(isSubmitting: true))
    }
}
