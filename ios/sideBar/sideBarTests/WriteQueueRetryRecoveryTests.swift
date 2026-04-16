import CoreData
import Foundation
import sideBarShared
import XCTest
@testable import sideBar

@MainActor
final class WriteQueueRetryRecoveryTests: XCTestCase {
    func testProcessQueueReplaysRetryableFailedWrite() async throws {
        let persistence = PersistenceController(inMemory: true)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let executor = TestWriteQueueExecutor()
        let queue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: connectivityMonitor,
            executor: executor,
            autoProcessEnabled: false
        )

        let writeId = UUID()
        let context = persistence.container.viewContext
        let write = PendingWrite.insertNew(in: context)
        write.id = writeId
        write.operationType = WriteOperation.delete.rawValue
        write.entityType = WriteEntityType.website.rawValue
        write.entityId = "website-1"
        write.payload = try JSONEncoder().encode(EmptyPayload())
        write.createdAt = Date()
        write.attempts = 5
        write.status = WriteQueueStatus.failed.rawValue
        write.lastError = String(describing: URLError(.cannotConnectToHost))
        try context.save()

        await queue.processQueue()

        XCTAssertEqual(executor.executedCount, 1)
        XCTAssertEqual(queue.pendingCount, 0)

        let request = PendingWrite.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", writeId as CVarArg)
        let remaining = try persistence.container.viewContext.fetch(request)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testProcessQueueLeavesTerminalFailedWriteUntouched() async throws {
        let persistence = PersistenceController(inMemory: true)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let executor = TestWriteQueueExecutor()
        let queue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: connectivityMonitor,
            executor: executor,
            autoProcessEnabled: false
        )

        let writeId = UUID()
        let context = persistence.container.viewContext
        let write = PendingWrite.insertNew(in: context)
        write.id = writeId
        write.operationType = WriteOperation.delete.rawValue
        write.entityType = WriteEntityType.website.rawValue
        write.entityId = "website-1"
        write.payload = try JSONEncoder().encode(EmptyPayload())
        write.createdAt = Date()
        write.attempts = 5
        write.status = WriteQueueStatus.failed.rawValue
        write.lastError = String(describing: APIClientError.requestFailed(400))
        try context.save()

        await queue.processQueue()

        XCTAssertEqual(executor.executedCount, 0)
        XCTAssertEqual(queue.pendingCount, 1)

        let request = PendingWrite.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", writeId as CVarArg)
        let refreshed = try XCTUnwrap(persistence.container.viewContext.fetch(request).first)
        XCTAssertEqual(refreshed.status, WriteQueueStatus.failed.rawValue)
        XCTAssertEqual(refreshed.attempts, 5)
    }
}

private struct EmptyPayload: Codable {}

private final class TestWriteQueueExecutor: WriteQueueExecutor {
    private(set) var executedCount = 0

    func execute(write: PendingWriteRecord) async throws {
        executedCount += 1
    }
}
