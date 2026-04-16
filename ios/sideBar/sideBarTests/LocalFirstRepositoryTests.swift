import XCTest
@testable import sideBar

@MainActor
final class LocalFirstRepositoryTests: XCTestCase {
    func testLoadDetailReturnsUnavailableOfflineWhenSnapshotMissing() async {
        var remoteLoadCallCount = 0
        let repository = LocalFirstRepository<String>(
            capabilityPolicy: {
                OfflineCapabilityPolicy(
                    isOffline: true,
                    isNetworkAvailable: false,
                    isServerReachable: false
                )
            },
            loadLocal: { _ in nil },
            loadRemote: { _ in
                remoteLoadCallCount += 1
                return "remote"
            }
        )

        let state = await repository.loadDetail(id: "note-1", force: false)

        XCTAssertNil(state.value)
        XCTAssertEqual(state.availability, .unavailableOffline)
        XCTAssertNil(state.source)
        XCTAssertEqual(remoteLoadCallCount, 0)
    }

    func testLoadDetailUsesLocalSnapshotBeforeAttemptingRemoteFetch() async {
        var remoteLoadCallCount = 0
        let repository = LocalFirstRepository<String>(
            capabilityPolicy: {
                OfflineCapabilityPolicy(
                    isOffline: false,
                    isNetworkAvailable: true,
                    isServerReachable: true
                )
            },
            loadLocal: { id in
                XCTAssertEqual(id, "note-1")
                return "cached"
            },
            loadRemote: { _ in
                remoteLoadCallCount += 1
                return "remote"
            }
        )

        let state = await repository.loadDetail(id: "note-1", force: false)

        XCTAssertEqual(state.value, "cached")
        XCTAssertEqual(state.availability, .available)
        XCTAssertEqual(state.source, .localSnapshot)
        XCTAssertEqual(remoteLoadCallCount, 0)
    }
}
