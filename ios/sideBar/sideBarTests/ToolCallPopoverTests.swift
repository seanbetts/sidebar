import XCTest
@testable import sideBar

@MainActor
final class ToolCallPopoverTests: XCTestCase {
    func testToolCallPopoverUsesCompactPopoverPanelType() {
        XCTAssertEqual(toolCallPopoverPanelType(), .compactPopover)
    }
}
