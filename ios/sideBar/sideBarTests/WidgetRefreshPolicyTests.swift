import Foundation
import XCTest
import sideBarShared
@testable import sideBar

final class WidgetRefreshPolicyTests: XCTestCase {
    func testTasksBecomeStaleAfterFiveMinutes() {
        let now = Date(timeIntervalSince1970: 1_000)
        let lastUpdated = now.addingTimeInterval(-5 * 60 - 1)

        XCTAssertTrue(
            WidgetRefreshPolicy.shouldRefresh(
                lastUpdated: lastUpdated,
                contentType: .tasks,
                now: now
            )
        )
    }

    func testNotesWebsitesAndFilesBecomeStaleAfterFifteenMinutes() {
        let now = Date(timeIntervalSince1970: 2_000)
        let lastUpdated = now.addingTimeInterval(-15 * 60 - 1)

        XCTAssertTrue(
            WidgetRefreshPolicy.shouldRefresh(
                lastUpdated: lastUpdated,
                contentType: .notes,
                now: now
            )
        )
        XCTAssertTrue(
            WidgetRefreshPolicy.shouldRefresh(
                lastUpdated: lastUpdated,
                contentType: .websites,
                now: now
            )
        )
        XCTAssertTrue(
            WidgetRefreshPolicy.shouldRefresh(
                lastUpdated: lastUpdated,
                contentType: .files,
                now: now
            )
        )
    }

    func testMissingSnapshotIsTreatedAsStale() {
        XCTAssertTrue(
            WidgetRefreshPolicy.shouldRefresh(
                lastUpdated: nil,
                contentType: .tasks,
                now: Date(timeIntervalSince1970: 3_000)
            )
        )
    }

    func testFreshSnapshotsDoNotTriggerRefresh() {
        let now = Date(timeIntervalSince1970: 4_000)

        XCTAssertFalse(
            WidgetRefreshPolicy.shouldRefresh(
                lastUpdated: now.addingTimeInterval(-4 * 60),
                contentType: .tasks,
                now: now
            )
        )
        XCTAssertFalse(
            WidgetRefreshPolicy.shouldRefresh(
                lastUpdated: now.addingTimeInterval(-14 * 60),
                contentType: .notes,
                now: now
            )
        )
    }

    func testDisplayOnlyWidgetsScheduleNextRefreshFromSnapshotAge() {
        let now = Date(timeIntervalSince1970: 5_000)
        let lastUpdated = now.addingTimeInterval(-5 * 60)
        let expectedRefresh = now.addingTimeInterval(10 * 60)

        XCTAssertEqual(
            WidgetRefreshPolicy.nextRefreshDate(
                lastUpdated: lastUpdated,
                contentType: .notes,
                now: now
            ),
            expectedRefresh
        )
        XCTAssertEqual(
            WidgetRefreshPolicy.nextRefreshDate(
                lastUpdated: lastUpdated,
                contentType: .websites,
                now: now
            ),
            expectedRefresh
        )
        XCTAssertEqual(
            WidgetRefreshPolicy.nextRefreshDate(
                lastUpdated: lastUpdated,
                contentType: .files,
                now: now
            ),
            expectedRefresh
        )
    }

    func testStaleDisplayOnlyWidgetsBackOffByOneThresholdAfterFailedRefreshWindow() {
        let now = Date(timeIntervalSince1970: 6_000)
        let lastUpdated = now.addingTimeInterval(-20 * 60)
        let expectedRefresh = now.addingTimeInterval(15 * 60)

        XCTAssertEqual(
            WidgetRefreshPolicy.nextRefreshDate(
                lastUpdated: lastUpdated,
                contentType: .notes,
                now: now
            ),
            expectedRefresh
        )
    }
}
