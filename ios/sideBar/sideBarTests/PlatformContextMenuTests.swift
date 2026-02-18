import XCTest
#if os(iOS)
import UIKit
#endif
@testable import sideBar

#if os(iOS)
final class PlatformContextMenuTests: XCTestCase {
    func testUIKitContextMenuIsDisabledOnIPhone() {
        XCTAssertFalse(shouldUseUIKitContextMenu(on: .phone))
    }

    func testUIKitContextMenuIsDisabledOnIPad() {
        XCTAssertFalse(shouldUseUIKitContextMenu(on: .pad))
    }
}
#endif
