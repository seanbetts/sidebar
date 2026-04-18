import XCTest
@testable import sideBar

@MainActor
final class TasksDetailViewTests: XCTestCase {
    func testExpandButtonUsesSharedGlassChrome() {
        XCTAssertEqual(TasksDetailView.expandButtonChromeStyle, .glass)
    }

    func testEmptyStateContentUsesAllTasksCompletedForToday() {
        XCTAssertEqual(
            TasksDetailView.emptyStateContent(for: .today, searchQuery: nil),
            .allTasksCompleted()
        )
    }

    func testEmptyStateContentUsesNoResultsForSearch() {
        XCTAssertEqual(
            TasksDetailView.emptyStateContent(
                for: .search(query: "ship"),
                searchQuery: "ship"
            ),
            .noResults(subtitle: "No results for \"ship\"")
        )
    }

    func testHeaderStatusLabelUsesTaskCountForNonEmptySelection() {
        XCTAssertEqual(
            TasksDetailView.headerStatus(
                totalCount: 3,
                selection: .today
            ),
            .count("3 tasks")
        )
    }

    func testHeaderStatusUsesCompletionIndicatorWhenSelectionIsEmpty() {
        XCTAssertEqual(
            TasksDetailView.headerStatus(
                totalCount: 0,
                selection: .today
            ),
            .complete
        )
    }

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
