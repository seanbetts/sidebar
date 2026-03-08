import XCTest
@testable import sideBar

final class SearchFieldTests: XCTestCase {
    func testDockChromeMatchesStandardVerticalPadding() {
        let standardPadding = SearchField.verticalPadding(for: .standard)
        let dockPadding = SearchField.verticalPadding(for: .dock)

        XCTAssertEqual(dockPadding, standardPadding)
    }
}
