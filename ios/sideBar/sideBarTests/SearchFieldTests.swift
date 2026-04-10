import XCTest
@testable import sideBar

final class SearchFieldTests: XCTestCase {
    func testStandardChromeUsesSharedFieldGlass() {
        let chrome = SearchField.backgroundChrome(for: .standard)

        XCTAssertEqual(chrome, .field)
    }

    func testDockChromeKeepsBackgroundTransparent() {
        let chrome = SearchField.backgroundChrome(for: .dock)

        XCTAssertNil(chrome)
    }

    func testDockChromeMatchesStandardVerticalPadding() {
        let standardPadding = SearchField.verticalPadding(for: .standard)
        let dockPadding = SearchField.verticalPadding(for: .dock)

        XCTAssertEqual(dockPadding, standardPadding)
        XCTAssertEqual(standardPadding, DesignTokens.Spacing.xxsPlus)
    }

    func testStandardChromeUsesSharedCompactFieldMinHeight() {
        XCTAssertEqual(
            SearchField.minHeight(for: .standard),
            DesignTokens.Size.compactFieldHeight
        )
    }
}
