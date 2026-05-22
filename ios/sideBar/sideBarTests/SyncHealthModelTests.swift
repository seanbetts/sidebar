import XCTest
@testable import sideBar

final class SyncHealthModelTests: XCTestCase {
    func testOfflineWhenServerReadsAreUnavailable() {
        let health = SyncHealthModel.evaluate(
            canAttemptServerRead: false,
            realtimeConnected: true,
            hasPendingReconnectRefresh: false,
            lastRefreshSucceeded: true
        )

        XCTAssertEqual(health, .offline)
    }

    func testDegradedWhenRealtimeDisconnectedButServerReadsAllowed() {
        let health = SyncHealthModel.evaluate(
            canAttemptServerRead: true,
            realtimeConnected: false,
            hasPendingReconnectRefresh: false,
            lastRefreshSucceeded: true
        )

        XCTAssertEqual(health, .degraded)
        XCTAssertTrue(health.allowsFallbackPolling)
    }

    func testReconnectingWhenRecoveryRefreshIsPending() {
        let health = SyncHealthModel.evaluate(
            canAttemptServerRead: true,
            realtimeConnected: true,
            hasPendingReconnectRefresh: true,
            lastRefreshSucceeded: false
        )

        XCTAssertEqual(health, .reconnecting)
    }
}
