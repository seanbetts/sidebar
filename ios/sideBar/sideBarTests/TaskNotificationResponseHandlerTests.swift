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
        let accountId = UUID().uuidString
        var completedTaskIds: [String] = []
        var openedRoutes: [URL] = []
        var completionCount = 0
        let handler = TaskNotificationResponseHandler(
            authContext: {
                TaskNotificationAuthContext(
                    authState: .active,
                    accountId: accountId.lowercased()
                )
            },
            refresh: { _ in },
            openRoute: { openedRoutes.append($0) },
            completeTask: {
                completedTaskIds.append($0)
                return .queued
            }
        )

        let result = await handler.handle(
            actionIdentifier: "TASK_MARK_COMPLETE",
            userInfo: Self.actionablePayload(taskId: taskId, accountId: accountId),
            completion: { completionCount += 1 }
        )

        XCTAssertEqual(result, .completionQueued)
        XCTAssertEqual(completedTaskIds, [taskId])
        XCTAssertTrue(openedRoutes.isEmpty)
        XCTAssertEqual(completionCount, 1)
    }

    func testCompletionAuthGate() async {
        let taskId = UUID().uuidString
        let accountId = UUID().uuidString
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
                authContext: {
                    TaskNotificationAuthContext(
                        authState: testCase.authState,
                        accountId: accountId
                    )
                },
                refresh: { _ in },
                openRoute: { _ in },
                completeTask: { _ in
                    completionCalls += 1
                    return .queued
                }
            )

            let result = await handler.handle(
                actionIdentifier: "TASK_MARK_COMPLETE",
                userInfo: Self.actionablePayload(taskId: taskId, accountId: accountId),
                completion: { callbackCalls += 1 }
            )

            XCTAssertEqual(result, testCase.expectedResult)
            XCTAssertEqual(completionCalls, testCase.expectedCompletionCalls)
            XCTAssertEqual(callbackCalls, 1)
        }
    }

    func testCompletionDeclinesNotificationFromPreviousAccount() async {
        let previousAccountId = UUID().uuidString
        let currentAccountId = UUID().uuidString
        var completionCalls = 0
        var callbackCalls = 0
        let handler = TaskNotificationResponseHandler(
            authContext: {
                TaskNotificationAuthContext(
                    authState: .active,
                    accountId: currentAccountId
                )
            },
            refresh: { _ in XCTFail("Account mismatch must not refresh") },
            openRoute: { _ in XCTFail("Account mismatch must not navigate") },
            completeTask: { _ in
                completionCalls += 1
                return .queued
            }
        )

        let result = await handler.handle(
            actionIdentifier: "TASK_MARK_COMPLETE",
            userInfo: Self.actionablePayload(
                taskId: UUID().uuidString,
                accountId: previousAccountId
            ),
            completion: { callbackCalls += 1 }
        )

        XCTAssertEqual(result, .completionDeclined)
        XCTAssertEqual(completionCalls, 0)
        XCTAssertEqual(callbackCalls, 1)
    }

    func testCompletionDeclinesMissingOrMalformedCurrentAccount() async {
        let notificationAccountId = UUID().uuidString
        let invalidCurrentAccountIds: [String?] = [nil, "", "  \n", "not-a-uuid"]

        for currentAccountId in invalidCurrentAccountIds {
            var completionCalls = 0
            var callbackCalls = 0
            let handler = TaskNotificationResponseHandler(
                authContext: {
                    currentAccountId.map {
                        TaskNotificationAuthContext(
                            authState: .staleRecoverable,
                            accountId: $0
                        )
                    }
                },
                refresh: { _ in XCTFail("Invalid account must not refresh") },
                openRoute: { _ in XCTFail("Invalid account must not navigate") },
                completeTask: { _ in
                    completionCalls += 1
                    return .queued
                }
            )

            let result = await handler.handle(
                actionIdentifier: "TASK_MARK_COMPLETE",
                userInfo: Self.actionablePayload(
                    taskId: UUID().uuidString,
                    accountId: notificationAccountId
                ),
                completion: { callbackCalls += 1 }
            )

            XCTAssertEqual(result, .completionDeclined)
            XCTAssertEqual(completionCalls, 0)
            XCTAssertEqual(callbackCalls, 1)
        }
    }

    func testQueueFailureReturnsStructuredOutcomeAndFinishesOnce() async {
        let accountId = UUID().uuidString
        var callbackCalls = 0
        let handler = TaskNotificationResponseHandler(
            authContext: {
                TaskNotificationAuthContext(authState: .active, accountId: accountId)
            },
            refresh: { _ in XCTFail("Queue failure must not refresh") },
            openRoute: { _ in XCTFail("Queue failure must not navigate") },
            completeTask: { _ in .failed(.queueFull) }
        )

        let result = await handler.handle(
            actionIdentifier: "TASK_MARK_COMPLETE",
            userInfo: Self.actionablePayload(taskId: UUID().uuidString, accountId: accountId),
            completion: { callbackCalls += 1 }
        )

        XCTAssertEqual(result, .completionFailed(.queueFull))
        XCTAssertEqual(callbackCalls, 1)
    }

    func testDefaultTapRefreshesAndOpensTodayWithoutCompleting() async throws {
        var refreshedPayloads: [[AnyHashable: Any]] = []
        var openedRoutes: [URL] = []
        var completionCalls = 0
        var callbackCalls = 0
        let handler = TaskNotificationResponseHandler(
            authContext: { nil },
            refresh: { refreshedPayloads.append($0) },
            openRoute: { openedRoutes.append($0) },
            completeTask: { _ in
                completionCalls += 1
                return .queued
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
            authContext: { nil },
            refresh: { _ in XCTFail("Summary completion must not refresh") },
            openRoute: { _ in XCTFail("Summary completion must not navigate") },
            completeTask: { _ in
                XCTFail("Summary completion must not complete")
                return .failed(.unavailable)
            }
        )

        let result = await handler.handle(
            actionIdentifier: "TASK_MARK_COMPLETE",
            userInfo: [
                "aps": ["category": "TASK_REMINDER_SUMMARY"],
                "notification_metadata": [
                    "task_id": UUID().uuidString,
                    "account_id": UUID().uuidString
                ]
            ],
            completion: { callbackCalls += 1 }
        )

        XCTAssertEqual(result, .ignored)
        XCTAssertEqual(callbackCalls, 1)
    }

    func testUnknownActionIsIgnoredAndFinishesOnce() async {
        var callbackCalls = 0
        let handler = TaskNotificationResponseHandler(
            authContext: { nil },
            refresh: { _ in XCTFail("Unknown action must not refresh") },
            openRoute: { _ in XCTFail("Unknown action must not navigate") },
            completeTask: { _ in
                XCTFail("Unknown action must not complete")
                return .failed(.unavailable)
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

    private static func actionablePayload(
        taskId: String,
        accountId: String
    ) -> [AnyHashable: Any] {
        [
            "aps": ["category": "TASK_REMINDER_ACTIONABLE"],
            "notification_metadata": [
                "task_id": taskId,
                "account_id": accountId
            ],
            "sidebar_route": "sidebar://tasks/today"
        ]
    }
}
