import XCTest
@testable import sideBar

@MainActor
final class WriteConflictResolutionSheetTests: XCTestCase {
    func testWriteConflictUsesDecisionSheetPanelType() {
        XCTAssertEqual(writeConflictPanelType(), .decisionSheet)
    }

    func testStoreSkillDetailUsesLargeInspectorPanelType() {
        XCTAssertEqual(storeSkillDetailPanelType(), .largeInspectorSheet)
    }
}
