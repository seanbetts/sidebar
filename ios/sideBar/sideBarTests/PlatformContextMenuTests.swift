import XCTest
#if os(iOS)
import UIKit
#endif
@testable import sideBar

#if os(iOS)
final class PlatformContextMenuTests: XCTestCase {
    func testUIKitContextMenuIsEnabledOnIPhoneForDestructiveMenus() {
        XCTAssertTrue(
            shouldUseUIKitContextMenu(
                on: .phone,
                items: [.delete {}]
            )
        )
    }

    func testUIKitContextMenuStaysDisabledOnIPhoneForNonDestructiveMenus() {
        XCTAssertFalse(
            shouldUseUIKitContextMenu(
                on: .phone,
                items: [.copy {}]
            )
        )
    }

    func testUIKitContextMenuStaysDisabledOnIPadForDestructiveMenus() {
        XCTAssertFalse(
            shouldUseUIKitContextMenu(
                on: .pad,
                items: [.delete {}]
            )
        )
    }
}
#endif
