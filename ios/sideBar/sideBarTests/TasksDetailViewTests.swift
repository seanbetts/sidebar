import XCTest
@testable import sideBar

final class TasksDetailViewTests: XCTestCase {
    func testShouldDisplayWorkspaceFloatingActionDockWhenNonCompactWithSelection() {
        XCTAssertTrue(
            TasksDetailView.shouldDisplayWorkspaceFloatingActionDock(
                isCompact: false,
                selection: .today
            )
        )
    }

    func testShouldDisplayWorkspaceFloatingActionDockWhenNonCompactGroupSelection() {
        XCTAssertTrue(
            TasksDetailView.shouldDisplayWorkspaceFloatingActionDock(
                isCompact: false,
                selection: .group(id: "group-1")
            )
        )
    }

    func testShouldDisplayWorkspaceFloatingActionDockWhenCompactHidesDock() {
        XCTAssertFalse(
            TasksDetailView.shouldDisplayWorkspaceFloatingActionDock(
                isCompact: true,
                selection: .today
            )
        )
    }

    func testShouldDisplayWorkspaceFloatingActionDockWithoutSelectionHidesDock() {
        XCTAssertFalse(
            TasksDetailView.shouldDisplayWorkspaceFloatingActionDock(
                isCompact: false,
                selection: .none
            )
        )
    }
}
