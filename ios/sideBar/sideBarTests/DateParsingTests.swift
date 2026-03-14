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

    func testParseISO8601MalformedInputReturnsNil() {
        XCTAssertNil(DateParsing.parseISO8601("not-a-date"))
    }

    func testParseISO8601TimeIntervalSince1970WithFractionalSeconds() {
        let interval = DateParsing.parseISO8601TimeIntervalSince1970("2024-01-01T12:00:00.123Z")

        XCTAssertEqual(interval, 1_704_110_400.123, accuracy: 0.000_1)
    }

    func testParseISO8601TimeIntervalSince1970WithoutFractionalSeconds() {
        let interval = DateParsing.parseISO8601TimeIntervalSince1970("2024-01-01T12:00:00Z")

        XCTAssertEqual(interval, 1_704_110_400, accuracy: 0.000_1)
    }

    func testParseISO8601TimeIntervalSince1970MalformedInputReturnsNil() {
        XCTAssertNil(DateParsing.parseISO8601TimeIntervalSince1970("not-a-date"))
    }
}
