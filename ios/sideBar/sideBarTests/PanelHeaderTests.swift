import SwiftUI
import XCTest
@testable import sideBar

final class PanelHeaderTests: XCTestCase {
    func testBackgroundStyleUsesSidebarOnIOSInLightMode() {
        let style = PanelHeader<EmptyView>.backgroundStyle(
            isMacOS: false,
            colorScheme: .light
        )

        XCTAssertEqual(style, .sidebar)
    }

    func testBackgroundStyleUsesSidebarOnIOSInDarkMode() {
        let style = PanelHeader<EmptyView>.backgroundStyle(
            isMacOS: false,
            colorScheme: .dark
        )

        XCTAssertEqual(style, .sidebar)
    }

    func testSearchablePanelHeaderMinHeightKeepsSearchRowWhenInlineSearchIsVisible() {
        let minHeight = LayoutMetrics.searchablePanelHeaderMinHeight(
            showsInlineSearch: true
        )

        XCTAssertEqual(minHeight, LayoutMetrics.panelHeaderMinHeight)
    }

    func testSearchablePanelHeaderMinHeightCollapsesRemovedSearchRowSpace() {
        let minHeight = LayoutMetrics.searchablePanelHeaderMinHeight(
            showsInlineSearch: false
        )

        XCTAssertEqual(minHeight, LayoutMetrics.appHeaderMinHeight)
    }
}
