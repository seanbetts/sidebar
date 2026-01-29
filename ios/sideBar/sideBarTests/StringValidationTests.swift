import XCTest
import sideBarShared
@testable import sideBar

final class StringValidationTests: XCTestCase {
    func testTrimmedRemovesWhitespace() {
        XCTAssertEqual("  hello\n".trimmed, "hello")
    }

    func testTrimmedOrNil() {
        XCTAssertNil("  \n".trimmedOrNil)
        XCTAssertEqual("  hi  ".trimmedOrNil, "hi")
    }

    func testIsBlank() {
        XCTAssertTrue(" \n".isBlank)
        XCTAssertFalse("ok".isBlank)
    }

    func testSubstringTrimmed() {
        let base = "  hello  "
        let substring = base.dropFirst().dropLast()
        XCTAssertEqual(substring.trimmed, "hello")
    }
}
