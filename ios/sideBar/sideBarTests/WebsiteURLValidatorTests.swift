import XCTest
@testable import sideBar

final class WebsiteURLValidatorTests: XCTestCase {
    func testValidatesUrlWithScheme() {
        XCTAssertTrue(WebsiteURLValidator.isValid("https://example.com"))
    }

    func testValidatesUrlWithoutScheme() {
        XCTAssertTrue(WebsiteURLValidator.isValid("example.com"))
    }

    func testRejectsLocalhost() {
        XCTAssertFalse(WebsiteURLValidator.isValid("http://localhost"))
    }

    func testRejectsIpAddress() {
        XCTAssertFalse(WebsiteURLValidator.isValid("http://127.0.0.1"))
    }

    func testRejectsMissingTld() {
        XCTAssertFalse(WebsiteURLValidator.isValid("https://example"))
    }
}
