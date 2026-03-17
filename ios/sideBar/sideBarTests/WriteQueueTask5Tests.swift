import CoreData
import Foundation
import XCTest
@testable import sideBar

@MainActor
final class WriteQueueTask5Tests: XCTestCase {
    func testProcessQueueRecoversInProgressWriteBeforeExecuting() async throws {
        let persistence = PersistenceController(inMemory: true)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let executor = Task5TestWriteExecutor()
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
        write.operationType = WriteOperation.update.rawValue
        write.entityType = WriteEntityType.note.rawValue
        write.entityId = "note-1"
        write.payload = Data()
        write.createdAt = Date()
        write.attempts = 1
        write.status = WriteQueueStatus.inProgress.rawValue
        try context.save()

        await queue.processQueue()

        XCTAssertEqual(executor.executedIds, [writeId])
        let remaining = try persistence.container.viewContext.fetch(PendingWrite.fetchRequest())
        XCTAssertTrue(remaining.isEmpty)
    }

    func testUnknownEntityTypeRemainsFailedForDebugging() async throws {
        let persistence = PersistenceController(inMemory: true)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let executor = CompositeWriteQueueExecutor(executors: [:])
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
        write.operationType = WriteOperation.update.rawValue
        write.entityType = "mystery_entity"
        write.entityId = "entity-1"
        write.payload = Data()
        write.createdAt = Date()
        write.attempts = 0
        write.status = WriteQueueStatus.pending.rawValue
        try context.save()

        await queue.processQueue()

        let request = PendingWrite.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", writeId as CVarArg)
        let remaining = try persistence.container.viewContext.fetch(request)
        let updated = try XCTUnwrap(remaining.first)
        XCTAssertEqual(updated.status, WriteQueueStatus.failed.rawValue)
        XCTAssertEqual(updated.attempts, 1)
        XCTAssertEqual(updated.entityType, "mystery_entity")
        XCTAssertNotNil(updated.lastError)
    }
}

private final class Task5TestWriteExecutor: WriteQueueExecutor {
    private(set) var executedIds: [UUID] = []

    func execute(write: PendingWriteRecord) async throws {
        executedIds.append(write.id)
    }
}
