import XCTest
@testable import sideBar

final class ToolCallPopoverTests: XCTestCase {
    func testToolCallPopoverUsesCompactPopoverPanelType() {
        XCTAssertEqual(toolCallPopoverPanelType(), .compactPopover)
    }
}
