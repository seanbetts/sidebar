import XCTest
@testable import sideBar

final class NotificationRouteTests: XCTestCase {
    func testTaskReminderPayloadRoutesToTasksToday() throws {
        let route = try XCTUnwrap(
            NotificationRoute(
                userInfo: [
                    "sidebar_route": "sidebar://tasks/today",
                    "notification_category": "task_reminder"
                ]
            )
        )

        XCTAssertEqual(route, .deepLink(try XCTUnwrap(URL(string: "sidebar://tasks/today"))))
    }

    func testAssistantReplyPayloadRoutesToConversation() throws {
        let route = try XCTUnwrap(
            NotificationRoute(
                userInfo: [
                    "sidebar_route": "sidebar://chat/conversation-123",
                    "notification_category": "assistant_reply"
                ]
            )
        )

        XCTAssertEqual(
            route,
            .deepLink(try XCTUnwrap(URL(string: "sidebar://chat/conversation-123")))
        )
    }

    func testMorningDigestPayloadRoutesToDigestDestination() throws {
        let route = try XCTUnwrap(
            NotificationRoute(
                userInfo: [
                    "sidebar_route": "sidebar://digest/morning",
                    "notification_category": "morning_digest"
                ]
            )
        )

        XCTAssertEqual(
            route,
            .deepLink(try XCTUnwrap(URL(string: "sidebar://digest/morning")))
        )
    }
}
