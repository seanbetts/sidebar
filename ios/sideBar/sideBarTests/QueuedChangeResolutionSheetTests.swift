import XCTest
@testable import sideBar

@MainActor
final class QueuedChangeResolutionSheetTests: XCTestCase {
    func testStoreSkillDetailUsesLargeInspectorPanelType() {
        XCTAssertEqual(storeSkillDetailPanelType(), .largeInspectorSheet)
    }
}
