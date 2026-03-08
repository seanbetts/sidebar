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
}
