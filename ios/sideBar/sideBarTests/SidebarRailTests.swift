import XCTest
@testable import sideBar

final class SidebarRailTests: XCTestCase {
    func testSidebarRailUsesSharedActionButtonChromeForActiveSections() {
        let chrome = SidebarRail.buttonChrome(isActive: true, isHovered: false)

        XCTAssertEqual(chrome, .actionButton)
    }

    func testSidebarRailUsesSharedActionButtonChromeForHoveredSections() {
        let chrome = SidebarRail.buttonChrome(isActive: false, isHovered: true)

        XCTAssertEqual(chrome, .actionButton)
    }

    func testSidebarRailKeepsInactiveSectionsChromeFree() {
        let chrome = SidebarRail.buttonChrome(isActive: false, isHovered: false)

        XCTAssertNil(chrome)
    }
}
