// swiftlint:disable file_length
import CoreData
import Foundation
import XCTest
@testable import sideBar

@MainActor
// swiftlint:disable:next type_body_length
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

    func testRetryAllWritesRequeuesFailedWriteAndProcessesIt() async throws {
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

        struct Payload: Codable {
            let value: String
        }

        let writeId = UUID()
        let context = persistence.container.viewContext
        let write = PendingWrite.insertNew(in: context)
        write.id = writeId
        write.operationType = WriteOperation.update.rawValue
        write.entityType = WriteEntityType.note.rawValue
        write.entityId = "note-1"
        write.payload = try JSONEncoder().encode(Payload(value: "Retry me"))
        write.createdAt = Date()
        write.attempts = 3
        write.status = WriteQueueStatus.failed.rawValue
        write.lastError = "Timeout"
        try context.save()

        await queue.retryAllWrites()

        XCTAssertEqual(executor.executedIds, [writeId])
        XCTAssertEqual(queue.pendingCount, 0)

        let request = PendingWrite.fetchRequest()
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

        let pending = try await queue.fetchPendingWrites()

        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.entityType, WriteEntityType.note.rawValue)
    }

    func testEnqueueTaskNotesUpdateCoalescesLatestPendingWrite() async throws {
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

        let first = TaskOperationPayload(
            operationId: "op-1",
            op: "notes",
            id: "task-1",
            notes: "First",
            clientUpdatedAt: "u1"
        )
        let second = TaskOperationPayload(
            operationId: "op-2",
            op: "notes",
            id: "task-1",
            notes: "Second",
            clientUpdatedAt: "u1"
        )

        try await queue.enqueue(
            operation: .update,
            entityType: .task,
            entityId: "task-1",
            payload: first
        )
        try await queue.enqueue(
            operation: .update,
            entityType: .task,
            entityId: "task-1",
            payload: second
        )

        let request = PendingWrite.fetchRequest()
        let writes = try persistence.container.viewContext.fetch(request)
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(queue.pendingCount, 1)

        let saved = try XCTUnwrap(writes.first)
        let decoded = try JSONDecoder().decode(TaskOperationPayload.self, from: saved.payload)
        XCTAssertEqual(decoded.operationId, "op-2")
        XCTAssertEqual(decoded.notes, "Second")
    }

    func testEnqueueTaskNonNotesUpdateDoesNotCoalesce() async throws {
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

        let first = TaskOperationPayload(
            operationId: "op-1",
            op: "rename",
            id: "task-1",
            title: "One",
            clientUpdatedAt: "u1"
        )
        let second = TaskOperationPayload(
            operationId: "op-2",
            op: "rename",
            id: "task-1",
            title: "Two",
            clientUpdatedAt: "u1"
        )

        try await queue.enqueue(
            operation: .update,
            entityType: .task,
            entityId: "task-1",
            payload: first
        )
        try await queue.enqueue(
            operation: .update,
            entityType: .task,
            entityId: "task-1",
            payload: second
        )

        let request = PendingWrite.fetchRequest()
        let writes = try persistence.container.viewContext.fetch(request)
        XCTAssertEqual(writes.count, 2)
        XCTAssertEqual(queue.pendingCount, 2)
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

        let pending = try await queue.fetchPendingWrites()
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
        let write = PendingWrite.insertNew(in: context)
        write.id = writeId
        write.operationType = WriteOperation.rename.rawValue
        write.entityType = WriteEntityType.file.rawValue
        write.entityId = "file-1"
        write.payload = Data()
        write.createdAt = Date()
        write.attempts = 2
        write.status = WriteQueueStatus.failed.rawValue
        write.lastError = "Conflict"
        write.conflictReason = "File changed"
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
        let write = PendingWrite.insertNew(in: context)
        write.id = writeId
        write.operationType = WriteOperation.rename.rawValue
        write.entityType = WriteEntityType.file.rawValue
        write.entityId = "file-1"
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

    func testFetchNextConflictReturnsOldestConflictAddedAfterStartupRecovery() async throws {
        let persistence = PersistenceController(inMemory: true)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let context = persistence.container.viewContext
        let bootstrapWrite = PendingWrite.insertNew(in: context)
        bootstrapWrite.id = UUID()
        bootstrapWrite.operationType = WriteOperation.update.rawValue
        bootstrapWrite.entityType = WriteEntityType.note.rawValue
        bootstrapWrite.entityId = "bootstrap-note"
        bootstrapWrite.payload = Data()
        bootstrapWrite.createdAt = Date(timeIntervalSince1970: 0)
        bootstrapWrite.attempts = 1
        bootstrapWrite.status = WriteQueueStatus.failed.rawValue
        try context.save()

        let queue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: connectivityMonitor,
            autoProcessEnabled: false
        )

        await waitUntilWriteQueueState {
            queue.pendingCount == 1
        }

        let firstId = UUID()
        let first = PendingWrite.insertNew(in: context)
        first.id = firstId
        first.operationType = WriteOperation.update.rawValue
        first.entityType = WriteEntityType.note.rawValue
        first.entityId = "note-1"
        first.payload = Data()
        first.createdAt = Date(timeIntervalSince1970: 1)
        first.attempts = 1
        first.status = WriteQueueStatus.failed.rawValue
        first.conflictReason = "First conflict"

        let second = PendingWrite.insertNew(in: context)
        second.id = UUID()
        second.operationType = WriteOperation.update.rawValue
        second.entityType = WriteEntityType.note.rawValue
        second.entityId = "note-2"
        second.payload = Data()
        second.createdAt = Date(timeIntervalSince1970: 2)
        second.attempts = 1
        second.status = WriteQueueStatus.failed.rawValue
        second.conflictReason = "Second conflict"

        try context.save()

        let next = try await queue.fetchNextConflict()
        XCTAssertEqual(next?.id, firstId)
        XCTAssertEqual(next?.conflictReason, "First conflict")
    }

    func testProcessQueueAutoResolvesConflictAndReplaysWrite() async throws {
        let persistence = PersistenceController(inMemory: true)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let executor = AutoResolvingConflictExecutor()
        let queue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: connectivityMonitor,
            executor: executor,
            autoProcessEnabled: false
        )

        let payload = TaskOperationPayload(
            operationId: "op-1",
            op: "rename",
            id: "task-1",
            title: "Local title",
            clientUpdatedAt: "2026-01-01T00:00:00Z"
        )

        try await queue.enqueue(
            operation: .update,
            entityType: .task,
            entityId: "task-1",
            payload: payload
        )

        await queue.processQueue()

        XCTAssertFalse(queue.isPausedForConflict)
        XCTAssertEqual(executor.receivedPayloads.count, 2)
        XCTAssertEqual(executor.receivedPayloads.first?.clientUpdatedAt, "2026-01-01T00:00:00Z")
        XCTAssertEqual(executor.receivedPayloads.last?.clientUpdatedAt, "2026-01-02T00:00:00Z")
        XCTAssertEqual(queue.pendingCount, 0)
        let nextConflict = try await queue.fetchNextConflict()
        XCTAssertNil(nextConflict)
    }
}

private final class TestWriteExecutor: WriteQueueExecutor {
    private(set) var executedIds: [UUID] = []

    func execute(write: PendingWriteRecord) async throws {
        executedIds.append(write.id)
    }
}

private final class AutoResolvingConflictExecutor: WriteQueueExecutor {
    let conflictReason = "Server has newer data"
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private(set) var receivedPayloads: [TaskOperationPayload] = []
    private var hasThrownConflict = false

    func execute(write: PendingWriteRecord) async throws {
        let payload = try decoder.decode(TaskOperationPayload.self, from: write.payload)
        receivedPayloads.append(payload)

        if !hasThrownConflict {
            hasThrownConflict = true
            let conflict = TaskSyncConflict(
                operationId: payload.operationId,
                op: payload.op,
                id: payload.id ?? "task-1",
                clientUpdatedAt: payload.clientUpdatedAt,
                serverUpdatedAt: "2026-01-02T00:00:00Z",
                serverTask: TaskItem(
                    id: payload.id ?? "task-1",
                    title: "Server title",
                    status: "open",
                    updatedAt: "2026-01-02T00:00:00Z"
                )
            )
            throw WriteQueueConflictError(
                reason: conflictReason,
                serverSnapshot: try encoder.encode(conflict)
            )
        }
    }
}

@MainActor
private func waitUntilWriteQueueState(
    timeoutNanoseconds: UInt64 = 200_000_000,
    condition: @escaping @MainActor () -> Bool
) async {
    let start = DispatchTime.now().uptimeNanoseconds
    while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
        if await condition() {
            return
        }
        await Task.yield()
    }

    let isSatisfied = await condition()
    if !isSatisfied {
        XCTFail("Condition was not met before timeout")
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
