import XCTest
@testable import sideBar

@MainActor
final class AIWorkLocalStoreTests: XCTestCase {
    func testSnapshotRoundTripsThroughOfflineStore() {
        let offlineStore = OfflineStore(container: PersistenceController(inMemory: true).container)
        let store = AIWorkLocalStore(offlineStore: offlineStore)
        let id = UUID()
        let snapshot = AIWorkSnapshot(
            id: id,
            capability: .liveNotes,
            status: .running,
            routeMetadata: .init(
                descriptor: .appleOnDevice(capability: .liveNotes),
                latencyMs: 25,
                structuredOutputValid: true,
                failureCategory: nil,
                contextBudget: nil
            ),
            payload: Data("{}".utf8),
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        store.save(snapshot)

        XCTAssertEqual(store.load(id: id, capability: .liveNotes), snapshot)
        XCTAssertNil(store.load(id: id, capability: .chat))
    }

    func testSnapshotKeyUsesCapabilityAndID() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

        XCTAssertEqual(
            CacheKeys.aiWork(capability: .liveNotes, id: id),
            "ai.work.live_notes.00000000-0000-0000-0000-000000000001"
        )
    }

    func testCleanupSnapshotsPrunesAIWorkEntries() async {
        let offlineStore = OfflineStore(container: PersistenceController(inMemory: true).container)
        let store = AIWorkLocalStore(offlineStore: offlineStore)

        for index in 1...3 {
            store.save(
                AIWorkSnapshot(
                    id: UUID(),
                    capability: .liveNotes,
                    status: .queued,
                    routeMetadata: nil,
                    payload: Data("{\"index\":\(index)}".utf8),
                    updatedAt: Date(timeIntervalSince1970: TimeInterval(index))
                )
            )
        }

        await offlineStore.cleanupSnapshots(retention: OfflineSnapshotRetention(maxAIWorkSnapshots: 2))

        let snapshots = offlineStore.getAll(keyPrefix: CacheKeys.aiWorkPrefix, as: AIWorkSnapshot.self)
        XCTAssertEqual(snapshots.count, 2)
    }
}
