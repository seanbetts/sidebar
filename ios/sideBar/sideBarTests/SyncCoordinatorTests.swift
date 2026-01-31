import Foundation
import XCTest
@testable import sideBar

@MainActor
final class SyncCoordinatorTests: XCTestCase {
    func testRefreshAllProcessesQueueAndStores() async throws {
        let persistence = PersistenceController(inMemory: true)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let executor = CountingWriteExecutor()
        let queue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: connectivityMonitor,
            executor: executor,
            autoProcessEnabled: false
        )

        struct Payload: Codable {
            let value: String
        }

        try await queue.enqueue(
            operation: .update,
            entityType: .note,
            entityId: "note-1",
            payload: Payload(value: "Hi")
        )

        let store = TestSyncStore()
        let coordinator = SyncCoordinator(
            connectivityMonitor: connectivityMonitor,
            writeQueue: queue,
            stores: [store]
        )

        await coordinator.refreshAll()

        XCTAssertEqual(executor.executedCount, 1)
        XCTAssertEqual(store.refreshCount, 1)
        XCTAssertEqual(queue.pendingCount, 0)
    }

    func testRefreshAllRespectsSyncAllowedGate() async throws {
        let persistence = PersistenceController(inMemory: true)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let executor = CountingWriteExecutor()
        let queue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: connectivityMonitor,
            executor: executor,
            autoProcessEnabled: false
        )

        struct Payload: Codable {
            let value: String
        }

        try await queue.enqueue(
            operation: .update,
            entityType: .note,
            entityId: "note-1",
            payload: Payload(value: "Hi")
        )

        let store = TestSyncStore()
        let coordinator = SyncCoordinator(
            connectivityMonitor: connectivityMonitor,
            writeQueue: queue,
            stores: [store],
            isSyncAllowed: { false }
        )

        await coordinator.refreshAll()

        XCTAssertEqual(executor.executedCount, 0)
        XCTAssertEqual(store.refreshCount, 0)
        XCTAssertEqual(queue.pendingCount, 1)
    }
}

@MainActor
private final class TestSyncStore: SyncableStore {
    private(set) var refreshCount = 0

    func refreshAll() async {
        refreshCount += 1
    }
}

private final class CountingWriteExecutor: WriteQueueExecutor {
    private(set) var executedCount = 0

    func execute(write: PendingWriteRecord) async throws {
        executedCount += 1
    }
}
