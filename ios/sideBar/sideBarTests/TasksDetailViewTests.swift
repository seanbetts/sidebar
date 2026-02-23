import XCTest
@testable import sideBar

final class TasksDetailViewTests: XCTestCase {
    func testShouldDisplayWorkspaceFloatingActionDockWhenNonCompactWithSelection() {
        XCTAssertTrue(
            TasksDetailView.shouldDisplayWorkspaceFloatingActionDock(
                isCompact: false,
                isPadIdiom: false,
                selection: .today
            )
        )
    }

    func testShouldDisplayWorkspaceFloatingActionDockWhenNonCompactGroupSelection() {
        XCTAssertTrue(
            TasksDetailView.shouldDisplayWorkspaceFloatingActionDock(
                isCompact: false,
                isPadIdiom: false,
                selection: .group(id: "group-1")
            )
        )
    }

    func testShouldDisplayWorkspaceFloatingActionDockWhenCompactHidesDock() {
        XCTAssertFalse(
            TasksDetailView.shouldDisplayWorkspaceFloatingActionDock(
                isCompact: true,
                isPadIdiom: false,
                selection: .today
            )
        )
    }

    func testShouldDisplayWorkspaceFloatingActionDockWithoutSelectionHidesDock() {
        XCTAssertFalse(
            TasksDetailView.shouldDisplayWorkspaceFloatingActionDock(
                isCompact: false,
                isPadIdiom: false,
                selection: .none
            )
        )
    }

    func testShouldDisplayWorkspaceFloatingActionDockOnIPadHidesDock() {
        XCTAssertFalse(
            TasksDetailView.shouldDisplayWorkspaceFloatingActionDock(
                isCompact: false,
                isPadIdiom: true,
                selection: .today
            )
        )
    }
}
