import XCTest
@testable import sideBar

final class WebsiteQueueDebugTraceTests: XCTestCase {
    func testIsEnabledRequiresExplicitOne() {
        XCTAssertTrue(
            WebsiteQueueDebugTrace.isEnabled(
                environment: [WebsiteQueueDebugTrace.environmentVariable: "1"]
            )
        )
        XCTAssertFalse(
            WebsiteQueueDebugTrace.isEnabled(
                environment: [WebsiteQueueDebugTrace.environmentVariable: "0"]
            )
        )
        XCTAssertFalse(WebsiteQueueDebugTrace.isEnabled(environment: [:]))
    }

    func testRenderIncludesDetailsInStableFormat() {
        let rendered = WebsiteQueueDebugTrace.render(
            event: "queued-websites.prune",
            details: ["context=reconcile", "saved_count=12", "queued_count=3"],
            uptime: "123.456"
        )

        XCTAssertEqual(
            rendered,
            "[WebsiteQueueDebug][+123.456] queued-websites.prune " +
                "context=reconcile saved_count=12 queued_count=3"
        )
    }
}
