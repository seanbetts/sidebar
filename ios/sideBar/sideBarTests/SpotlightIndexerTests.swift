import XCTest
@testable import sideBar

final class SpotlightIndexerTests: XCTestCase {
    func testDeepLinkURLMapsTaskIdentifiersToTasksSection() {
        let url = SpotlightIndexer.deepLinkURL(from: "task:task-123")

        XCTAssertEqual(url, URL(string: "sidebar://tasks"))
    }

    func testDeepLinkURLRejectsEmptyTaskIdentifier() {
        XCTAssertNil(SpotlightIndexer.deepLinkURL(from: "task:"))
    }
}
