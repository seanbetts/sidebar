import XCTest
@testable import sideBar

final class SidebarMenuItemTests: XCTestCase {
    func testShareMenuItemFactoryUsesExpectedMetadata() {
        var didInvoke = false
        let item = SidebarMenuItem.share {
            didInvoke = true
        }

        XCTAssertEqual(item.title, "Share URL")
        XCTAssertEqual(item.systemImage, "square.and.arrow.up.on.square")
        XCTAssertNil(item.role)

        item.handler()
        XCTAssertTrue(didInvoke)
    }

    func testShareTextMenuItemFactoryUsesExpectedMetadata() {
        var didInvoke = false
        let item = SidebarMenuItem.shareText {
            didInvoke = true
        }

        XCTAssertEqual(item.title, "Share Text")
        XCTAssertEqual(item.systemImage, "square.and.arrow.up.on.square")
        XCTAssertNil(item.role)

        item.handler()
        XCTAssertTrue(didInvoke)
    }
}
