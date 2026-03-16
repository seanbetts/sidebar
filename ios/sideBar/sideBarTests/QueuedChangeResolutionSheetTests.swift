import XCTest
@testable import sideBar

@MainActor
final class QueuedChangeResolutionSheetTests: XCTestCase {
    func testQueuedChangeResolutionUsesDecisionSheetPanelType() {
        XCTAssertEqual(queuedChangeResolutionPanelType(), .decisionSheet)
    }

    func testStoreSkillDetailUsesLargeInspectorPanelType() {
        XCTAssertEqual(storeSkillDetailPanelType(), .largeInspectorSheet)
    }
}
