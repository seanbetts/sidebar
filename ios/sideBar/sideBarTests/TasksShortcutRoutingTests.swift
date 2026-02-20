import XCTest
@testable import sideBar

final class TasksShortcutRoutingTests: XCTestCase {
    func testTasksDetailShortcutActionDoesNotRequireActiveTaskForNewItem() {
        XCTAssertTrue(TasksDetailView.shortcutActionDoesNotRequireActiveTask(.newItem))
    }

    func testTasksDetailShortcutActionRequiresActiveTaskForTaskActions() {
        XCTAssertFalse(TasksDetailView.shortcutActionDoesNotRequireActiveTask(.completeTask))
        XCTAssertFalse(TasksDetailView.shortcutActionDoesNotRequireActiveTask(.deleteItem))
    }

    func testTasksPanelDeepLinkDecisionInCompactPanelList() {
        XCTAssertTrue(
            TasksPanelView.shouldDeepLinkForCompactNewTask(
                isCompact: true,
                tasksPhoneDetailRouteId: nil
            )
        )
    }

    func testTasksPanelDeepLinkDecisionInCompactDetailRoute() {
        XCTAssertFalse(
            TasksPanelView.shouldDeepLinkForCompactNewTask(
                isCompact: true,
                tasksPhoneDetailRouteId: TaskSelection.today.cacheKey
            )
        )
    }

    func testTasksPanelDeepLinkDecisionInRegularLayout() {
        XCTAssertFalse(
            TasksPanelView.shouldDeepLinkForCompactNewTask(
                isCompact: false,
                tasksPhoneDetailRouteId: nil
            )
        )
    }
}
