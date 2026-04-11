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
            SearchField.minHeight(for: .standard, option: .system),
            DesignTokens.Size.compactFieldHeight,
            accuracy: 0.0001
        )
    }

    func testSearchFieldMetricsScaleWithAppTextSize() {
        XCTAssertLessThan(
            SearchField.minHeight(for: .standard, option: .small),
            SearchField.minHeight(for: .standard, option: .system)
        )
        XCTAssertGreaterThan(
            SearchField.minHeight(for: .standard, option: .large),
            SearchField.minHeight(for: .standard, option: .system)
        )
        XCTAssertLessThan(
            SearchField.verticalPadding(for: .standard, option: .small),
            SearchField.verticalPadding(for: .standard, option: .system)
        )
        XCTAssertGreaterThan(
            SearchField.verticalPadding(for: .standard, option: .large),
            SearchField.verticalPadding(for: .standard, option: .system)
        )
    }
}
