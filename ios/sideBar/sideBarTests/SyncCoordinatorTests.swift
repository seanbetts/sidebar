import Foundation
import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class SyncCoordinatorTests: XCTestCase {
    func testRefreshAllProcessesQueueBeforeRunningReconnectRefresh() async throws {
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

        let refreshHandler = TestReconnectRefreshHandler()
        let coordinator = SyncCoordinator(
            connectivityMonitor: connectivityMonitor,
            writeQueue: queue,
            onReconnectRefresh: { await refreshHandler.run() }
        )

        await coordinator.refreshAll()

        XCTAssertEqual(executor.executedCount, 1)
        XCTAssertEqual(refreshHandler.refreshCount, 1)
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

        let refreshHandler = TestReconnectRefreshHandler()
        let coordinator = SyncCoordinator(
            connectivityMonitor: connectivityMonitor,
            writeQueue: queue,
            onReconnectRefresh: { await refreshHandler.run() },
            isSyncAllowed: { false }
        )

        await coordinator.refreshAll()

        XCTAssertEqual(executor.executedCount, 0)
        XCTAssertEqual(refreshHandler.refreshCount, 0)
        XCTAssertEqual(queue.pendingCount, 1)
    }

    func testRefreshAllSkipsQueueAndReconnectRefreshWhenServerIsUnreachable() async throws {
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

        let refreshHandler = TestReconnectRefreshHandler()
        let coordinator = SyncCoordinator(
            connectivityMonitor: connectivityMonitor,
            writeQueue: queue,
            onReconnectRefresh: { await refreshHandler.run() }
        )

        await coordinator.refreshAll()

        XCTAssertEqual(executor.executedCount, 0)
        XCTAssertEqual(refreshHandler.refreshCount, 0)
        XCTAssertEqual(queue.pendingCount, 1)
    }
}

@MainActor
private final class TestReconnectRefreshHandler {
    private(set) var refreshCount = 0

    func run() async {
        refreshCount += 1
    }
}

private final class CountingWriteExecutor: WriteQueueExecutor {
    private(set) var executedCount = 0

    func execute(write: PendingWriteRecord) async throws {
        executedCount += 1
    }
}

private func waitForCoordinatorDrain() async {
    await Task.yield()
    try? await Task.sleep(nanoseconds: 50_000_000)
}
