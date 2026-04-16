import CoreData
import Foundation
import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class WriteQueueOfflineCapabilityTests: XCTestCase {
    func testProcessQueueDoesNotExecuteWhenServerUnreachable() async throws {
        let persistence = PersistenceController(inMemory: true)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let executor = OfflineCapabilityTestWriteExecutor()
        let queue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: connectivityMonitor,
            executor: executor,
            autoProcessEnabled: false
        )

        try await enqueuePendingWrite(in: queue)
        await forceServerUnreachable(connectivityMonitor)
        await queue.processQueue()

        XCTAssertTrue(executor.executedIds.isEmpty)

        let writes = try persistence.container.viewContext.fetch(PendingWrite.fetchRequest())
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(writes.first?.status, WriteQueueStatus.pending.rawValue)
    }

    func testEnqueueDoesNotAutoProcessUntilServerReachable() async throws {
        let persistence = PersistenceController(inMemory: true)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let executor = OfflineCapabilityTestWriteExecutor()
        await forceServerUnreachable(connectivityMonitor)

        let queue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: connectivityMonitor,
            executor: executor,
            autoProcessEnabled: true
        )

        try await enqueuePendingWrite(in: queue)
        await waitForQueueDrain()
        XCTAssertTrue(executor.executedIds.isEmpty)

        NotificationCenter.default.post(name: .apiClientRequestSucceeded, object: nil)
        NotificationCenter.default.post(name: .apiClientRequestSucceeded, object: nil)
        await waitForQueueExecution { !executor.executedIds.isEmpty }

        XCTAssertEqual(executor.executedIds.count, 1)
        let writes = try persistence.container.viewContext.fetch(PendingWrite.fetchRequest())
        XCTAssertTrue(writes.isEmpty)
    }
}

@MainActor
private extension WriteQueueOfflineCapabilityTests {
    struct Payload: Codable {
        let value: String
    }

    func enqueuePendingWrite(in queue: WriteQueue) async throws {
        try await queue.enqueue(
            operation: .update,
            entityType: .note,
            entityId: "note-1",
            payload: Payload(value: "Hello")
        )
    }

    func forceServerUnreachable(_ connectivityMonitor: ConnectivityMonitor, attempts: Int = 20) async {
        for _ in 0..<2 {
            NotificationCenter.default.post(
                name: .apiClientRequestFailed,
                object: nil,
                userInfo: ["error": URLError(.cannotConnectToHost)]
            )
        }

        for _ in 0..<attempts where connectivityMonitor.isServerReachable {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertTrue(connectivityMonitor.isNetworkAvailable)
        XCTAssertFalse(connectivityMonitor.isOffline)
        XCTAssertFalse(connectivityMonitor.isServerReachable)
    }

    func waitForQueueDrain(attempts: Int = 20) async {
        for _ in 0..<attempts {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func waitForQueueExecution(
        attempts: Int = 40,
        condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<attempts where !condition() {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(condition())
    }
}

private final class OfflineCapabilityTestWriteExecutor: WriteQueueExecutor {
    private(set) var executedIds: [UUID] = []

    func execute(write: PendingWriteRecord) async throws {
        executedIds.append(write.id)
    }
}
