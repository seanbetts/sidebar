import CoreData
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

        try await queue.enqueue(
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

        try await queue.enqueue(
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

        try await queue.enqueue(
            operation: .update,
            entityType: .note,
            entityId: "note-1",
            payload: Payload(value: "Hi")
        )

        let pending = await queue.fetchPendingWrites()

        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.entityType, WriteEntityType.note.rawValue)
    }

    func testQueueRespectsMaxPendingWrites() async throws {
        let persistence = PersistenceController(inMemory: true)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let queue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: connectivityMonitor,
            autoProcessEnabled: false,
            maxPendingWrites: 1
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

        await XCTAssertThrowsErrorAsync {
            try await queue.enqueue(
                operation: .update,
                entityType: .note,
                entityId: "note-2",
                payload: Payload(value: "Hi")
            )
        }
    }

    func testPruneOldestWritesKeepsMostRecent() async throws {
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

        try await queue.enqueue(
            operation: .update,
            entityType: .note,
            entityId: "note-1",
            payload: Payload(value: "One")
        )
        try await queue.enqueue(
            operation: .update,
            entityType: .note,
            entityId: "note-2",
            payload: Payload(value: "Two")
        )
        try await queue.enqueue(
            operation: .update,
            entityType: .note,
            entityId: "note-3",
            payload: Payload(value: "Three")
        )

        await queue.pruneOldestWrites(keeping: 1)

        let pending = await queue.fetchPendingWrites()
        XCTAssertEqual(pending.count, 1)
    }

    func testResolveConflictKeepLocalResetsPendingWrite() async throws {
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

        let writeId = UUID()
        let context = persistence.container.viewContext
        let write = PendingWrite(context: context)
        write.id = writeId
        write.operationType = WriteOperation.update.rawValue
        write.entityType = WriteEntityType.note.rawValue
        write.entityId = "note-1"
        write.payload = Data()
        write.createdAt = Date()
        write.attempts = 2
        write.status = WriteQueueStatus.failed.rawValue
        write.lastError = "Conflict"
        write.conflictReason = "Note changed"
        write.serverSnapshot = Data("snapshot".utf8)
        try context.save()

        await queue.resolveConflict(id: writeId, resolution: .keepLocal)

        let request = PendingWrite.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", writeId as CVarArg)
        let refreshed = try persistence.container.viewContext.fetch(request)
        let updated = try XCTUnwrap(refreshed.first)
        XCTAssertEqual(updated.status, WriteQueueStatus.pending.rawValue)
        XCTAssertEqual(updated.attempts, 0)
        XCTAssertNil(updated.conflictReason)
        XCTAssertNil(updated.serverSnapshot)
    }

    func testResolveConflictKeepServerDeletesPendingWrite() async throws {
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

        let writeId = UUID()
        let context = persistence.container.viewContext
        let write = PendingWrite(context: context)
        write.id = writeId
        write.operationType = WriteOperation.update.rawValue
        write.entityType = WriteEntityType.note.rawValue
        write.entityId = "note-1"
        write.payload = Data()
        write.createdAt = Date()
        write.attempts = 1
        write.status = WriteQueueStatus.failed.rawValue
        try context.save()

        await queue.resolveConflict(id: writeId, resolution: .keepServer)

        let request = PendingWrite.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", writeId as CVarArg)
        let remaining = try persistence.container.viewContext.fetch(request)
        XCTAssertTrue(remaining.isEmpty)
    }
}

private final class TestWriteExecutor: WriteQueueExecutor {
    private(set) var executedIds: [UUID] = []

    func execute(write: PendingWriteRecord) async throws {
        executedIds.append(write.id)
    }
}

@MainActor
private func XCTAssertThrowsErrorAsync(_ expression: @escaping () async throws -> Void) async {
    do {
        try await expression()
        XCTFail("Expected error to be thrown")
    } catch {
        // expected
    }
}
