import XCTest
@testable import sideBar

final class TasksDetailViewTests: XCTestCase {
    func testShouldDisplayWorkspaceFloatingActionDockWhenNonCompactWithSelection() {
        XCTAssertTrue(
            TasksDetailView.shouldDisplayWorkspaceFloatingActionDock(
                isCompact: false,
                isPhoneIdiom: true,
                selection: .today
            )
        )
    }

    func testShouldDisplayWorkspaceFloatingActionDockWhenNonCompactGroupSelection() {
        XCTAssertTrue(
            TasksDetailView.shouldDisplayWorkspaceFloatingActionDock(
                isCompact: false,
                isPhoneIdiom: true,
                selection: .group(id: "group-1")
            )
        )
    }

    func testShouldDisplayWorkspaceFloatingActionDockWhenCompactHidesDock() {
        XCTAssertFalse(
            TasksDetailView.shouldDisplayWorkspaceFloatingActionDock(
                isCompact: true,
                isPhoneIdiom: true,
                selection: .today
            )
        )
    }

    func testShouldDisplayWorkspaceFloatingActionDockWithoutSelectionHidesDock() {
        XCTAssertFalse(
            TasksDetailView.shouldDisplayWorkspaceFloatingActionDock(
                isCompact: false,
                isPhoneIdiom: true,
                selection: .none
            )
        )
    }

    func testShouldDisplayWorkspaceFloatingActionDockOnNonPhoneHidesDock() {
        XCTAssertFalse(
            TasksDetailView.shouldDisplayWorkspaceFloatingActionDock(
                isCompact: false,
                isPhoneIdiom: false,
                selection: .today
            )
        )
    }
}
