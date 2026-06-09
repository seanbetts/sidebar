import XCTest
@testable import sideBar

@MainActor
final class LocalFirstWriteContractTests: XCTestCase {
    func testNormalCrudMutationsDoNotGateOnOfflinePolicy() async throws {
        let policy = OfflineCapabilityPolicy(
            isOffline: false,
            isNetworkAvailable: true,
            isServerReachable: true
        )

        XCTAssertTrue(policy.canAttemptServerWrite)
        XCTAssertFalse(policy.shouldQueueWrites)
    }
}
