import XCTest
#if os(iOS)
import UIKit
#endif
@testable import sideBar

#if os(iOS)
final class PlatformContextMenuTests: XCTestCase {
    func testUIKitContextMenuIsEnabledOnIPhone() {
        XCTAssertTrue(shouldUseUIKitContextMenu(on: .phone))
    }

    func testUIKitContextMenuIsEnabledOnIPad() {
        XCTAssertTrue(shouldUseUIKitContextMenu(on: .pad))
    }
}
#endif
