import XCTest
@testable import sideBar

final class ChatMessageListViewScrollBehaviorTests: XCTestCase {
    func testStreamingAutoScrollAllowsFirstUpdate() {
        var controller = ChatStreamingAutoScrollController(throttleSeconds: 0.08)

        let shouldScroll = controller.shouldScroll(now: Date(timeIntervalSince1970: 100))

        XCTAssertTrue(shouldScroll)
    }

    func testStreamingAutoScrollThrottlesRapidUpdates() {
        var controller = ChatStreamingAutoScrollController(throttleSeconds: 0.08)
        _ = controller.shouldScroll(now: Date(timeIntervalSince1970: 100))

        let shouldScroll = controller.shouldScroll(now: Date(timeIntervalSince1970: 100.04))

        XCTAssertFalse(shouldScroll)
    }

    func testStreamingAutoScrollAllowsUpdateAfterThrottleInterval() {
        var controller = ChatStreamingAutoScrollController(throttleSeconds: 0.08)
        _ = controller.shouldScroll(now: Date(timeIntervalSince1970: 100))
        _ = controller.shouldScroll(now: Date(timeIntervalSince1970: 100.04))

        let shouldScroll = controller.shouldScroll(now: Date(timeIntervalSince1970: 100.10))

        XCTAssertTrue(shouldScroll)
    }

    func testStreamingAutoScrollResetAllowsImmediateScroll() {
        var controller = ChatStreamingAutoScrollController(throttleSeconds: 0.08)
        _ = controller.shouldScroll(now: Date(timeIntervalSince1970: 100))
        _ = controller.shouldScroll(now: Date(timeIntervalSince1970: 100.04))
        controller.reset()

        let shouldScroll = controller.shouldScroll(now: Date(timeIntervalSince1970: 100.05))

        XCTAssertTrue(shouldScroll)
    }
}
