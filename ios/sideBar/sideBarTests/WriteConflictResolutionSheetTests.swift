import XCTest
@testable import sideBar

final class WriteConflictResolutionSheetTests: XCTestCase {
    func testWriteConflictUsesDecisionSheetPanelType() {
        XCTAssertEqual(writeConflictPanelType(), .decisionSheet)
    }

    func testStoreSkillDetailUsesLargeInspectorPanelType() {
        XCTAssertEqual(storeSkillDetailPanelType(), .largeInspectorSheet)
    }
}
