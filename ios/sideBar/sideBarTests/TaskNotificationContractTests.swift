import UserNotifications
import XCTest
@testable import sideBar

@MainActor
final class TaskNotificationContractTests: XCTestCase {
    func testCategoriesExposeBackgroundCompletionOnlyForActionableTasks() throws {
        let categories = Dictionary(
            uniqueKeysWithValues: TaskNotificationContract.categories().map { ($0.identifier, $0) }
        )
        let actionable = try XCTUnwrap(categories["TASK_REMINDER_ACTIONABLE"])
        let summary = try XCTUnwrap(categories["TASK_REMINDER_SUMMARY"])

        XCTAssertEqual(actionable.actions.map(\.identifier), ["TASK_MARK_COMPLETE"])
        XCTAssertEqual(actionable.actions.first?.title, "Mark Complete")
        XCTAssertEqual(actionable.actions.first?.options, UNNotificationActionOptions())
        XCTAssertTrue(summary.actions.isEmpty)
        XCTAssertEqual(TaskNotificationContract.threadIdentifier, "task-reminders")
    }

    func testCompletionResponseRequiresNestedCanonicalTaskID() {
        let taskId = UUID().uuidString
        let response = TaskNotificationContract.response(
            actionIdentifier: "TASK_MARK_COMPLETE",
            userInfo: [
                "notification_metadata": ["task_id": taskId]
            ]
        )

        XCTAssertEqual(response, .complete(taskId: taskId))
        XCTAssertEqual(
            TaskNotificationContract.response(
                actionIdentifier: "TASK_MARK_COMPLETE",
                userInfo: ["notification_metadata": ["task_id": "not-a-uuid"]]
            ),
            .ignore
        )
        XCTAssertEqual(
            TaskNotificationContract.response(
                actionIdentifier: "UNKNOWN_ACTION",
                userInfo: ["notification_metadata": ["task_id": taskId]]
            ),
            .ignore
        )
    }

    func testSummaryResponseCannotCompleteTask() {
        XCTAssertEqual(
            TaskNotificationContract.response(
                actionIdentifier: "TASK_MARK_COMPLETE",
                userInfo: [
                    "aps": ["category": "TASK_REMINDER_SUMMARY"],
                    "notification_metadata": ["task_id": UUID().uuidString]
                ]
            ),
            .ignore
        )
    }

    func testDefaultTapIsClassifiedWithoutTaskMutation() {
        XCTAssertEqual(
            TaskNotificationContract.response(
                actionIdentifier: UNNotificationDefaultActionIdentifier,
                userInfo: ["sidebar_route": "sidebar://tasks/today"]
            ),
            .defaultTap
        )
    }
}
