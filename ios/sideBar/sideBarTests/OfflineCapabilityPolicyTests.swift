import XCTest
@testable import sideBar

@MainActor
final class OfflineCapabilityPolicyTests: XCTestCase {
    func testCapabilityPolicyTreatsServerUnreachableAsOfflineForWrites() {
        let policy = OfflineCapabilityPolicy(
            isOffline: false,
            isNetworkAvailable: true,
            isServerReachable: false
        )

        XCTAssertTrue(policy.canReadLocal)
        XCTAssertFalse(policy.canAttemptServerRead)
        XCTAssertFalse(policy.canAttemptServerWrite)
        XCTAssertTrue(policy.shouldQueueWrites)
    }

    func testNetworkStatusProvidesSharedCapabilityPolicy() {
        let status = TestNetworkStatus(
            isNetworkAvailable: true,
            isOffline: false,
            isServerReachable: false
        )

        XCTAssertEqual(
            status.offlineCapabilityPolicy,
            OfflineCapabilityPolicy(
                isOffline: false,
                isNetworkAvailable: true,
                isServerReachable: false
            )
        )
    }
}

private struct TestNetworkStatus: NetworkStatusProviding {
    let isNetworkAvailable: Bool
    let isOffline: Bool
    let isServerReachable: Bool
}
