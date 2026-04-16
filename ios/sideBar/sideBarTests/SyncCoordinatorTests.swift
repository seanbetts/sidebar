import Foundation
import XCTest
import sideBarShared
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

    func testRefreshAllSkipsQueueAndStoresWhenServerIsUnreachable() async throws {
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

        NotificationCenter.default.post(
            name: .apiClientRequestFailed,
            object: nil,
            userInfo: ["error": URLError(.cannotConnectToHost)]
        )
        await waitForCoordinatorDrain()
        NotificationCenter.default.post(
            name: .apiClientRequestFailed,
            object: nil,
            userInfo: ["error": URLError(.cannotConnectToHost)]
        )
        await waitForCoordinatorDrain()

        let store = TestSyncStore()
        let coordinator = SyncCoordinator(
            connectivityMonitor: connectivityMonitor,
            writeQueue: queue,
            stores: [store]
        )

        await coordinator.refreshAll()

        XCTAssertEqual(executor.executedCount, 0)
        XCTAssertEqual(store.refreshCount, 0)
        XCTAssertEqual(queue.pendingCount, 1)
    }

    func testRefreshAllStartsSecondStoreBeforeFirstStoreFinishes() async {
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let queue = WriteQueue(
            container: PersistenceController(inMemory: true).container,
            connectivityMonitor: connectivityMonitor,
            autoProcessEnabled: false
        )
        let firstStore = BlockingSyncStore()
        let secondStore = OrderedSyncStore()
        let coordinator = SyncCoordinator(
            connectivityMonitor: connectivityMonitor,
            writeQueue: queue,
            stores: [firstStore, secondStore]
        )

        let refreshTask = Task {
            await coordinator.refreshAll()
        }

        await fulfillment(of: [firstStore.started], timeout: 1.0)
        await fulfillment(of: [secondStore.started], timeout: 1.0)
        XCTAssertEqual(secondStore.refreshCount, 1)

        firstStore.continueRefresh()
        await refreshTask.value

        XCTAssertEqual(secondStore.refreshCount, 1)
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

@MainActor
private final class BlockingSyncStore: SyncableStore {
    let started = XCTestExpectation(description: "blocking store started")
    private var continuation: CheckedContinuation<Void, Never>?

    func refreshAll() async {
        started.fulfill()
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func continueRefresh() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class OrderedSyncStore: SyncableStore {
    let started = XCTestExpectation(description: "ordered store started")
    private(set) var refreshCount = 0

    func refreshAll() async {
        started.fulfill()
        refreshCount += 1
    }
}

private func waitForCoordinatorDrain() async {
    await Task.yield()
    try? await Task.sleep(nanoseconds: 50_000_000)
}
