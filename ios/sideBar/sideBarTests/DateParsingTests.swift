import XCTest
import sideBarShared
@testable import sideBar

final class DateParsingTests: XCTestCase {
    func testParseISO8601WithFractionalSeconds() {
        let date = DateParsing.parseISO8601("2024-01-01T12:00:00.123Z")
        XCTAssertNotNil(date)
    }

    func testParseISO8601WithoutFractionalSeconds() {
        let date = DateParsing.parseISO8601("2024-01-01T12:00:00Z")
        XCTAssertNotNil(date)
    }

    func testParseISO8601NilInputReturnsNil() {
        XCTAssertNil(DateParsing.parseISO8601(nil))
    }
}
