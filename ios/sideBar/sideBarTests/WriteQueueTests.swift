import Foundation
import XCTest
@testable import sideBar

@MainActor
final class WriteQueueTests: XCTestCase {
    func testEnqueueCreatesPendingWrite() async throws {
        let persistence = PersistenceController(inMemory: true)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let queue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: connectivityMonitor,
            autoProcessEnabled: false
        )

        struct Payload: Codable, Equatable {
            let value: String
        }

        try queue.enqueue(
            operation: .update,
            entityType: .note,
            entityId: "note-1",
            payload: Payload(value: "Hello")
        )

        let request = PendingWrite.fetchRequest()
        let writes = try persistence.container.viewContext.fetch(request)

        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(queue.pendingCount, 1)

        let write = try XCTUnwrap(writes.first)
        XCTAssertEqual(write.operationType, WriteOperation.update.rawValue)
        XCTAssertEqual(write.entityType, WriteEntityType.note.rawValue)
        XCTAssertEqual(write.entityId, "note-1")
        XCTAssertEqual(write.status, WriteQueueStatus.pending.rawValue)
        XCTAssertEqual(write.attempts, 0)
    }

    func testProcessQueueExecutesAndDeletesPendingWrite() async throws {
        let persistence = PersistenceController(inMemory: true)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let executor = TestWriteExecutor()
        let queue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: connectivityMonitor,
            executor: executor,
            autoProcessEnabled: false
        )

        struct Payload: Codable, Equatable {
            let value: String
        }

        try queue.enqueue(
            operation: .create,
            entityType: .message,
            entityId: nil,
            payload: Payload(value: "Hi")
        )

        let request = PendingWrite.fetchRequest()
        let writes = try persistence.container.viewContext.fetch(request)
        let writeId = try XCTUnwrap(writes.first?.id)

        await queue.processQueue()

        XCTAssertEqual(executor.executedIds, [writeId])
        XCTAssertEqual(queue.pendingCount, 0)

        let remaining = try persistence.container.viewContext.fetch(request)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testFetchPendingWritesReturnsQueuedItems() async throws {
        let persistence = PersistenceController(inMemory: true)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let queue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: connectivityMonitor,
            autoProcessEnabled: false
        )

        struct Payload: Codable {
            let value: String
        }

        try queue.enqueue(
            operation: .update,
            entityType: .note,
            entityId: "note-1",
            payload: Payload(value: "Hi")
        )

        let pending = queue.fetchPendingWrites()

        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.entityType, WriteEntityType.note.rawValue)
    }
}

private final class TestWriteExecutor: WriteQueueExecutor {
    private(set) var executedIds: [UUID] = []

    func execute(write: PendingWrite) async throws {
        executedIds.append(write.id)
    }
}
