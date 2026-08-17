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

    func testCompletionResponseRequiresNestedCanonicalTaskAndAccountIDs() {
        let taskId = UUID().uuidString
        let accountId = UUID().uuidString
        let response = TaskNotificationContract.response(
            actionIdentifier: "TASK_MARK_COMPLETE",
            userInfo: [
                "aps": ["category": "TASK_REMINDER_ACTIONABLE"],
                "notification_metadata": [
                    "task_id": taskId,
                    "account_id": accountId
                ]
            ]
        )

        XCTAssertEqual(response, .complete(taskId: taskId, accountId: accountId))
    }

    func testCompletionResponseRequiresActionableCategory() {
        XCTAssertEqual(
            TaskNotificationContract.response(
                actionIdentifier: "TASK_MARK_COMPLETE",
                userInfo: [
                    "notification_metadata": [
                        "task_id": UUID().uuidString,
                        "account_id": UUID().uuidString
                    ]
                ]
            ),
            .ignore
        )
    }

    func testCompletionResponseRejectsInvalidTaskIdentifiers() {
        let accountId = UUID().uuidString
        let invalidMetadata: [[AnyHashable: Any]] = [
            ["account_id": accountId],
            ["task_id": "", "account_id": accountId],
            ["task_id": "  \n", "account_id": accountId],
            ["task_id": 42, "account_id": accountId],
            ["task_id": "not-a-uuid", "account_id": accountId]
        ]

        for metadata in invalidMetadata {
            XCTAssertEqual(
                TaskNotificationContract.response(
                    actionIdentifier: "TASK_MARK_COMPLETE",
                    userInfo: [
                        "aps": ["category": "TASK_REMINDER_ACTIONABLE"],
                        "notification_metadata": metadata
                    ]
                ),
                .ignore
            )
        }
    }

    func testCompletionResponseRejectsInvalidAccountIdentifiers() {
        let taskId = UUID().uuidString
        let invalidMetadata: [[AnyHashable: Any]] = [
            ["task_id": taskId],
            ["task_id": taskId, "account_id": ""],
            ["task_id": taskId, "account_id": "  \n"],
            ["task_id": taskId, "account_id": 42],
            ["task_id": taskId, "account_id": "not-a-uuid"]
        ]

        for metadata in invalidMetadata {
            XCTAssertEqual(
                TaskNotificationContract.response(
                    actionIdentifier: "TASK_MARK_COMPLETE",
                    userInfo: [
                        "aps": ["category": "TASK_REMINDER_ACTIONABLE"],
                        "notification_metadata": metadata
                    ]
                ),
                .ignore
            )
        }
    }

    func testUnknownActionCannotCompleteTask() {
        let taskId = UUID().uuidString
        let accountId = UUID().uuidString
        XCTAssertEqual(
            TaskNotificationContract.response(
                actionIdentifier: "UNKNOWN_ACTION",
                userInfo: [
                    "notification_metadata": [
                        "task_id": taskId,
                        "account_id": accountId
                    ]
                ]
            ),
            .ignore
        )
    }

    func testSummaryResponseCannotCompleteTask() {
        let accountId = UUID().uuidString
        XCTAssertEqual(
            TaskNotificationContract.response(
                actionIdentifier: "TASK_MARK_COMPLETE",
                userInfo: [
                    "aps": ["category": "TASK_REMINDER_SUMMARY"],
                    "notification_metadata": [
                        "task_id": UUID().uuidString,
                        "account_id": accountId
                    ]
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

    func testDeliveredCleanupTargetsOnlyActionableTaskNotifications() {
        let deliveries = [
            TaskNotificationDelivery(
                requestIdentifier: "actionable-task",
                categoryIdentifier: "TASK_REMINDER_ACTIONABLE"
            ),
            TaskNotificationDelivery(
                requestIdentifier: "overdue-summary",
                categoryIdentifier: "TASK_REMINDER_SUMMARY"
            ),
            TaskNotificationDelivery(
                requestIdentifier: "unrelated",
                categoryIdentifier: "ASSISTANT_NOTIFICATION"
            )
        ]

        XCTAssertEqual(
            TaskNotificationContract.deliveredActionableRequestIdentifiers(in: deliveries),
            ["actionable-task"]
        )
    }
}
