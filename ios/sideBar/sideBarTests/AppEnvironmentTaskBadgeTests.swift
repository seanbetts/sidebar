import XCTest
@testable import sideBar

final class AppEnvironmentTaskBadgeTests: XCTestCase {
    func testTaskBadgeCountClearsWhenSignedOut() {
        let count = AppEnvironment.taskBadgeCount(
            authState: .signedOut,
            counts: TaskCountsResponse(
                generatedAt: nil,
                counts: TaskCounts(today: 3, upcoming: 1, completed: 0),
                projects: [],
                groups: []
            )
        )

        XCTAssertEqual(count, 0)
    }

    func testTaskBadgeCountUsesTodayCountWhenAuthenticated() {
        let count = AppEnvironment.taskBadgeCount(
            authState: .active,
            counts: TaskCountsResponse(
                generatedAt: nil,
                counts: TaskCounts(today: 3, upcoming: 1, completed: 0),
                projects: [],
                groups: []
            )
        )

        XCTAssertEqual(count, 3)
    }

    func testTaskBadgeCountDefaultsToZeroWhenCountsMissing() {
        let count = AppEnvironment.taskBadgeCount(
            authState: .staleRecoverable,
            counts: nil
        )

        XCTAssertEqual(count, 0)
    }

    #if os(macOS)
    func testMacBadgeLabelClearsZeroCounts() {
        XCTAssertNil(LiveTaskBadgeUpdater.badgeLabel(for: 0))
    }

    func testMacBadgeLabelRendersPositiveCounts() {
        XCTAssertEqual(LiveTaskBadgeUpdater.badgeLabel(for: 3), "3")
    }
    #endif
}
