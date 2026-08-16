import UserNotifications
import XCTest
@testable import sideBar

private struct CompletionAuthCase {
    let authState: AuthState
    let expectedResult: TaskNotificationHandlingResult
    let expectedCompletionCalls: Int
}

@MainActor
final class TaskNotificationResponseHandlerTests: XCTestCase {
    func testCompleteQueuesQuietlyAndFinishesOnce() async {
        let taskId = UUID().uuidString
        var completedTaskIds: [String] = []
        var openedRoutes: [URL] = []
        var completionCount = 0
        let handler = TaskNotificationResponseHandler(
            authState: { .active },
            refresh: { _ in },
            openRoute: { openedRoutes.append($0) },
            completeTask: {
                completedTaskIds.append($0)
                return true
            }
        )

        let result = await handler.handle(
            actionIdentifier: "TASK_MARK_COMPLETE",
            userInfo: ["notification_metadata": ["task_id": taskId]],
            completion: { completionCount += 1 }
        )

        XCTAssertEqual(result, .completionQueued)
        XCTAssertEqual(completedTaskIds, [taskId])
        XCTAssertTrue(openedRoutes.isEmpty)
        XCTAssertEqual(completionCount, 1)
    }

    func testCompletionAuthGate() async {
        let taskId = UUID().uuidString
        let cases = [
            CompletionAuthCase(
                authState: .active,
                expectedResult: .completionQueued,
                expectedCompletionCalls: 1
            ),
            CompletionAuthCase(
                authState: .staleRecoverable,
                expectedResult: .completionQueued,
                expectedCompletionCalls: 1
            ),
            CompletionAuthCase(
                authState: .signedOut,
                expectedResult: .completionDeclined,
                expectedCompletionCalls: 0
            ),
            CompletionAuthCase(
                authState: .reauthenticationRequired,
                expectedResult: .completionDeclined,
                expectedCompletionCalls: 0
            )
        ]

        for testCase in cases {
            var completionCalls = 0
            var callbackCalls = 0
            let handler = TaskNotificationResponseHandler(
                authState: { testCase.authState },
                refresh: { _ in },
                openRoute: { _ in },
                completeTask: { _ in
                    completionCalls += 1
                    return true
                }
            )

            let result = await handler.handle(
                actionIdentifier: "TASK_MARK_COMPLETE",
                userInfo: ["notification_metadata": ["task_id": taskId]],
                completion: { callbackCalls += 1 }
            )

            XCTAssertEqual(result, testCase.expectedResult)
            XCTAssertEqual(completionCalls, testCase.expectedCompletionCalls)
            XCTAssertEqual(callbackCalls, 1)
        }
    }

    func testQueueFailureIsDeclinedAndFinishesOnce() async {
        var callbackCalls = 0
        let handler = TaskNotificationResponseHandler(
            authState: { .active },
            refresh: { _ in },
            openRoute: { _ in },
            completeTask: { _ in false }
        )

        let result = await handler.handle(
            actionIdentifier: "TASK_MARK_COMPLETE",
            userInfo: ["notification_metadata": ["task_id": UUID().uuidString]],
            completion: { callbackCalls += 1 }
        )

        XCTAssertEqual(result, .completionDeclined)
        XCTAssertEqual(callbackCalls, 1)
    }

    func testDefaultTapRefreshesAndOpensTodayWithoutCompleting() async throws {
        var refreshedPayloads: [[AnyHashable: Any]] = []
        var openedRoutes: [URL] = []
        var completionCalls = 0
        var callbackCalls = 0
        let handler = TaskNotificationResponseHandler(
            authState: { .active },
            refresh: { refreshedPayloads.append($0) },
            openRoute: { openedRoutes.append($0) },
            completeTask: { _ in
                completionCalls += 1
                return true
            }
        )
        let userInfo: [AnyHashable: Any] = ["sidebar_route": "sidebar://tasks/today"]

        let result = await handler.handle(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: userInfo,
            completion: { callbackCalls += 1 }
        )

        XCTAssertEqual(result, .opened)
        XCTAssertEqual(refreshedPayloads.count, 1)
        XCTAssertEqual(refreshedPayloads.first?["sidebar_route"] as? String, "sidebar://tasks/today")
        XCTAssertEqual(
            openedRoutes,
            [try XCTUnwrap(URL(string: "sidebar://tasks/today"))]
        )
        XCTAssertEqual(completionCalls, 0)
        XCTAssertEqual(callbackCalls, 1)
    }

    func testSummaryCompletionIsIgnoredAndFinishesOnce() async {
        var callbackCalls = 0
        let handler = TaskNotificationResponseHandler(
            authState: { .active },
            refresh: { _ in XCTFail("Summary completion must not refresh") },
            openRoute: { _ in XCTFail("Summary completion must not navigate") },
            completeTask: { _ in
                XCTFail("Summary completion must not complete")
                return false
            }
        )

        let result = await handler.handle(
            actionIdentifier: "TASK_MARK_COMPLETE",
            userInfo: [
                "aps": ["category": "TASK_REMINDER_SUMMARY"],
                "notification_metadata": ["task_id": UUID().uuidString]
            ],
            completion: { callbackCalls += 1 }
        )

        XCTAssertEqual(result, .ignored)
        XCTAssertEqual(callbackCalls, 1)
    }

    func testUnknownActionIsIgnoredAndFinishesOnce() async {
        var callbackCalls = 0
        let handler = TaskNotificationResponseHandler(
            authState: { .active },
            refresh: { _ in XCTFail("Unknown action must not refresh") },
            openRoute: { _ in XCTFail("Unknown action must not navigate") },
            completeTask: { _ in
                XCTFail("Unknown action must not complete")
                return false
            }
        )

        let result = await handler.handle(
            actionIdentifier: "UNKNOWN_ACTION",
            userInfo: [:],
            completion: { callbackCalls += 1 }
        )

        XCTAssertEqual(result, .ignored)
        XCTAssertEqual(callbackCalls, 1)
    }
}
