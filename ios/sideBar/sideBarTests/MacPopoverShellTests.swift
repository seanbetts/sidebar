import SwiftUI
import XCTest
@testable import sideBar

final class MacPopoverShellTests: XCTestCase {
    func testMacPopoverShellUsesSharedPopoverChrome() {
        XCTAssertEqual(MacPopoverShell<EmptyView>.chromeKind, .popoverShell)
    }

    func testCompactPopoverUsesCompactMinimumWidth() {
        XCTAssertEqual(MacPopoverShell<EmptyView>.minimumWidth(for: .compactPopover), 280)
    }

    func testEditorPopoverUsesWideMaximumWidth() {
        XCTAssertEqual(MacPopoverShell<EmptyView>.maximumWidth(for: .editorSheet), 640)
    }
}
