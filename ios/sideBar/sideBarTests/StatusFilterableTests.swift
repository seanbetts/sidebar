import XCTest
import sideBarShared
@testable import sideBar

final class StatusFilterableTests: XCTestCase {
    private struct Item: StatusFilterable {
        let statusValue: String
    }

    func testFiltersByStatus() {
        let items = [
            Item(statusValue: "ready"),
            Item(statusValue: "failed"),
            Item(statusValue: "processing"),
            Item(statusValue: ""),
            Item(statusValue: "canceled")
        ]

        XCTAssertEqual(items.readyItems.count, 1)
        XCTAssertEqual(items.failedItems.count, 1)
        XCTAssertEqual(items.activeItems.count, 1)
        XCTAssertEqual(items.activeItems.first?.statusValue, "processing")
        XCTAssertTrue(items.hasActiveItems)
    }

    func testHasActiveItemsFalseWhenOnlyTerminalOrBlank() {
        let items = [
            Item(statusValue: "ready"),
            Item(statusValue: "failed"),
            Item(statusValue: ""),
            Item(statusValue: "canceled")
        ]

        XCTAssertFalse(items.hasActiveItems)
    }

    func testFiltersAreCaseAndWhitespaceInsensitive() {
        let items = [
            Item(statusValue: " READY "),
            Item(statusValue: "  FAILED"),
            Item(statusValue: " Queued ")
        ]

        XCTAssertEqual(items.readyItems.count, 1)
        XCTAssertEqual(items.failedItems.count, 1)
        XCTAssertEqual(items.activeItems.count, 1)
        XCTAssertEqual(items.activeItems.first?.statusValue, " Queued ")
        XCTAssertTrue(items.hasActiveItems)
    }
}
