import XCTest
@testable import sideBar

final class MacWindowFramePersistenceTests: XCTestCase {
    func testGeneratedSwiftUIWindowFrameKeysAreClassifiedAsUnstable() {
        let defaultsDomain = [
            "NSWindow Frame SwiftUI.SceneBridgeReader-1-AppWindow-1": "-2830 233 2264 1276 -3360 -90 3360 1890 ",
            "NSWindow Frame SwiftUI.OtherWindow-1-AppWindow-1": "-2307 216 2009 1477 -3360 -90 3360 1890 ",
            "NSWindow Frame main": "583 213 2344 1426 0 0 3200 1800 ",
            "sideBar.didRequestBadgePermission": true
        ] as [String : Any]

        XCTAssertEqual(
            MacWindowFramePersistence.unstableGeneratedFrameKeys(in: defaultsDomain).sorted(),
            [
                "NSWindow Frame SwiftUI.OtherWindow-1-AppWindow-1",
                "NSWindow Frame SwiftUI.SceneBridgeReader-1-AppWindow-1"
            ]
        )
    }

    func testGeneratedWindowFrameClassifierPreservesStableMainKey() {
        let defaultsDomain = [
            "NSWindow Frame main": "583 213 2344 1426 0 0 3200 1800 ",
            "NSWindow Frame com_apple_SwiftUI_Settings_window": "-1643 702 900 492 -3360 -90 3360 1890 "
        ] as [String : Any]

        XCTAssertEqual(
            MacWindowFramePersistence.unstableGeneratedFrameKeys(in: defaultsDomain),
            []
        )
    }
}
