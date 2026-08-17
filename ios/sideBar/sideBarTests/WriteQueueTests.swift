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

    func testOverlappingProcessRequestReplaysWriteDeferredByCurrentDrain() async throws {
        let persistence = PersistenceController(inMemory: true)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let barrier = OverlappingDrainBarrier()
        let executor = DeferredThenSuccessfulWriteExecutor(barrier: barrier)
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
            entityType: .task,
            entityId: "task-1",
            payload: Payload(value: "complete")
        )
        let writeId = try XCTUnwrap(
            persistence.container.viewContext.fetch(PendingWrite.fetchRequest()).first?.id
        )

        let initialDrain = Task { @MainActor in await queue.processQueue() }
        await barrier.waitUntilFirstAttemptStarts()
        let overlappingDrain = Task { @MainActor in
            barrier.signalOverlappingRequest()
            await queue.processQueue()
        }
        await initialDrain.value
        await overlappingDrain.value

        XCTAssertEqual(executor.attemptedIds, [writeId, writeId])
        XCTAssertEqual(executor.successfulIds, [writeId])
        XCTAssertEqual(queue.pendingCount, 0)
        let remaining = try persistence.container.viewContext.fetch(PendingWrite.fetchRequest())
        XCTAssertTrue(remaining.isEmpty)
    }

    func testFullDrainRequestedDuringTargetedRetryRunsBeforeBothCallersFinish() async throws {
        let persistence = PersistenceController(inMemory: true)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let legacyWriteId = UUID()
        let notificationWriteId = UUID()
        let barrier = TargetedRetryBarrier()
        let executor = TargetedRetryBarrierExecutor(
            targetedWriteId: legacyWriteId,
            barrier: barrier
        )
        let queue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: connectivityMonitor,
            executor: executor,
            autoProcessEnabled: false
        )
        let notificationPayload = TaskAccountBoundOperationPayload(
            operation: TaskOperationPayload(
                operationId: "notification-complete",
                op: "complete",
                id: "notification-task"
            ),
            accountScope: TaskNotificationAccountScope(
                accountId: UUID(),
                generationId: UUID()
            )
        )
        try await queue.enqueue(
            operation: .update,
            entityType: .task,
            entityId: "notification-task",
            payload: notificationPayload,
            writeId: notificationWriteId
        )
        try insertFailedLegacyWrite(
            id: legacyWriteId,
            context: persistence.container.viewContext
        )

        let manualRetry = Task { @MainActor in try await queue.retryWrite(id: legacyWriteId) }
        await barrier.waitUntilTargetedRetryStarts()
        let recoveryProbe = FullDrainCompletionProbe()
        let recoveryDrain = Task { @MainActor in
            recoveryProbe.markStarted()
            await queue.processQueue()
            recoveryProbe.markFinished()
        }
        await recoveryProbe.waitUntilStarted()
        await Task.yield()

        XCTAssertFalse(recoveryProbe.didFinish)
        barrier.releaseTargetedRetry()
        try await manualRetry.value
        await waitUntilWriteQueueState {
            recoveryProbe.didFinish && !queue.isProcessing
        }
        if recoveryProbe.didFinish {
            await recoveryDrain.value
        } else {
            recoveryDrain.cancel()
        }

        XCTAssertEqual(executor.attemptedIds, [legacyWriteId, notificationWriteId])
        XCTAssertEqual(executor.successfulIds, [legacyWriteId, notificationWriteId])
        XCTAssertEqual(queue.pendingCount, 0)
        let remaining = try persistence.container.viewContext.fetch(PendingWrite.fetchRequest())
        XCTAssertTrue(remaining.isEmpty)
    }

    func testProcessQueueCancellationDuringRetrySleepDoesNotMarkAdditionalAttempts() async throws {
        let persistence = PersistenceController(inMemory: true)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let executor = TestWriteExecutor(error: MockError.forced)
        let sleepProbe = WriteQueueSleepProbe()
        let queue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: connectivityMonitor,
            executor: executor,
            autoProcessEnabled: false,
            retrySleep: sleepProbe.sleep
        )
        await waitUntilWriteQueueState {
            queue.hasRecoveredStuckWrites && queue.hasRecoveredConflictWrites
        }

        struct Payload: Codable {
            let value: String
        }
        try await queue.enqueue(
            operation: .update,
            entityType: .note,
            entityId: "note-1",
            payload: Payload(value: "retry")
        )

        let task = Task { await queue.processQueue() }
        while sleepProbe.sleepCallCount == 0 {
            await Task.yield()
        }
        task.cancel()
        sleepProbe.failSleepsWithCancellation()
        await task.value

        let request = PendingWrite.fetchRequest()
        let writes = try persistence.container.viewContext.fetch(request)
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(writes.first?.attempts, 1)
        XCTAssertEqual(writes.first?.status, WriteQueueStatus.pending.rawValue)
        XCTAssertFalse(queue.isProcessing)
        XCTAssertFalse(queue.isExecutingWrite)
    }

    func testProcessQueueExecutorCancellationRestoresPendingWrite() async throws {
        let persistence = PersistenceController(inMemory: true)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let executor = TestWriteExecutor(error: CancellationError())
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
            payload: Payload(value: "cancel")
        )

        await queue.processQueue()

        let request = PendingWrite.fetchRequest()
        let writes = try persistence.container.viewContext.fetch(request)
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(writes.first?.attempts, 1)
        XCTAssertEqual(writes.first?.status, WriteQueueStatus.pending.rawValue)
        XCTAssertNil(writes.first?.lastError)
        XCTAssertFalse(queue.isProcessing)
        XCTAssertFalse(queue.isExecutingWrite)
    }

    func testProcessQueueCancellationAfterExecutorSuccessDeletesWrite() async throws {
        let persistence = PersistenceController(inMemory: true)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let executor = CancellingAfterSuccessWriteExecutor()
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
            operation: .create,
            entityType: .message,
            entityId: nil,
            payload: Payload(value: "created remotely")
        )

        await queue.processQueue()

        let request = PendingWrite.fetchRequest()
        let writes = try persistence.container.viewContext.fetch(request)
        XCTAssertTrue(writes.isEmpty)
        XCTAssertEqual(executor.executedIds.count, 1)
        XCTAssertFalse(queue.isProcessing)
        XCTAssertFalse(queue.isExecutingWrite)
    }

    func testProcessRetriedWriteExecutorCancellationRestoresOriginalState() async throws {
        let persistence = PersistenceController(inMemory: true)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let executor = TestWriteExecutor(error: CancellationError())
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
        let originalLastAttemptAt = Date(timeIntervalSince1970: 1_700_000_000)
        let context = persistence.container.viewContext
        let write = PendingWrite.insertNew(in: context)
        write.id = writeId
        write.operationType = WriteOperation.update.rawValue
        write.entityType = WriteEntityType.note.rawValue
        write.entityId = "note-1"
        write.payload = try JSONEncoder().encode(Payload(value: "retry"))
        write.createdAt = Date()
        write.attempts = 3
        write.status = WriteQueueStatus.pending.rawValue
        write.lastAttemptAt = originalLastAttemptAt
        try context.save()

        await queue.processRetriedWrite(id: writeId)

        let request = PendingWrite.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", writeId as CVarArg)
        let writes = try persistence.container.viewContext.fetch(request)
        let restored = try XCTUnwrap(writes.first)
        XCTAssertEqual(restored.status, WriteQueueStatus.pending.rawValue)
        XCTAssertEqual(restored.attempts, 3)
        XCTAssertEqual(restored.lastAttemptAt, originalLastAttemptAt)
        XCTAssertNil(restored.lastError)
        XCTAssertFalse(queue.isProcessing)
        XCTAssertFalse(queue.isExecutingWrite)
    }

    func testProcessRetriedWriteRetrySleepCancellationRestoresOriginalState() async throws {
        let persistence = PersistenceController(inMemory: true)
        let connectivityMonitor = ConnectivityMonitor(
            baseUrl: URL(string: "http://localhost")!,
            startMonitoring: false
        )
        let executor = TestWriteExecutor(error: MockError.forced)
        let sleepProbe = WriteQueueSleepProbe()
        let queue = WriteQueue(
            container: persistence.container,
            connectivityMonitor: connectivityMonitor,
            executor: executor,
            autoProcessEnabled: false,
            retrySleep: sleepProbe.sleep
        )
        await waitUntilWriteQueueState {
            queue.hasRecoveredStuckWrites && queue.hasRecoveredConflictWrites
        }

        struct Payload: Codable {
            let value: String
        }
        let writeId = UUID()
        let originalLastAttemptAt = Date(timeIntervalSince1970: 1_700_000_000)
        let originalServerSnapshot = Data("snapshot".utf8)
        let context = persistence.container.viewContext
        let write = PendingWrite.insertNew(in: context)
        write.id = writeId
        write.operationType = WriteOperation.update.rawValue
        write.entityType = WriteEntityType.note.rawValue
        write.entityId = "note-1"
        write.payload = try JSONEncoder().encode(Payload(value: "retry"))
        write.createdAt = Date()
        write.attempts = 3
        write.status = WriteQueueStatus.pending.rawValue
        write.lastError = "Previous error"
        write.lastAttemptAt = originalLastAttemptAt
        write.conflictReason = "Previous conflict"
        write.serverSnapshot = originalServerSnapshot
        try context.save()

        let task = Task { await queue.processRetriedWrite(id: writeId) }
        while sleepProbe.sleepCallCount == 0 {
            await Task.yield()
        }
        task.cancel()
        sleepProbe.failSleepsWithCancellation()
        await task.value

        let request = PendingWrite.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", writeId as CVarArg)
        let writes = try persistence.container.viewContext.fetch(request)
        let restored = try XCTUnwrap(writes.first)
        XCTAssertEqual(restored.status, WriteQueueStatus.pending.rawValue)
        XCTAssertEqual(restored.attempts, 3)
        XCTAssertEqual(restored.lastAttemptAt, originalLastAttemptAt)
        XCTAssertEqual(restored.lastError, "Previous error")
        XCTAssertEqual(restored.conflictReason, "Previous conflict")
        XCTAssertEqual(restored.serverSnapshot, originalServerSnapshot)
        XCTAssertFalse(queue.isProcessing)
        XCTAssertFalse(queue.isExecutingWrite)
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

    func testEnqueueSettingsPatchCoalescesLatestPendingWrite() async throws {
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

        let first = SettingsMutationPayload(
            communicationStyle: "Concise",
            name: "Ada Lovelace"
        )
        let second = SettingsMutationPayload(
            workingRelationship: "Operator",
            jobTitle: "Rear Admiral"
        )

        try await queue.enqueue(
            operation: .update,
            entityType: .settings,
            entityId: "settings",
            payload: first
        )
        try await queue.enqueue(
            operation: .update,
            entityType: .settings,
            entityId: "settings",
            payload: second
        )

        let request = PendingWrite.fetchRequest()
        let writes = try persistence.container.viewContext.fetch(request)
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(queue.pendingCount, 1)

        let saved = try XCTUnwrap(writes.first)
        let decoded = try JSONDecoder().decode(SettingsMutationPayload.self, from: saved.payload)
        XCTAssertEqual(decoded.communicationStyle, "Concise")
        XCTAssertEqual(decoded.workingRelationship, "Operator")
        XCTAssertEqual(decoded.name, "Ada Lovelace")
        XCTAssertEqual(decoded.jobTitle, "Rear Admiral")
        XCTAssertEqual(decoded.kind, .settingsPatch)
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

        await waitUntilWriteQueueState {
            queue.hasRecoveredStuckWrites
                && queue.hasRecoveredConflictWrites
                && queue.pendingCount == 0
        }

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
    private let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func execute(write: PendingWriteRecord) async throws {
        if let error {
            throw error
        }
        executedIds.append(write.id)
    }
}

@MainActor
private final class OverlappingDrainBarrier {
    private var didStartFirstAttempt = false
    private var didSignalOverlappingRequest = false
    private var firstAttemptStartedContinuation: CheckedContinuation<Void, Never>?
    private var overlappingRequestContinuation: CheckedContinuation<Void, Never>?

    func suspendFirstAttemptUntilOverlap() async {
        didStartFirstAttempt = true
        firstAttemptStartedContinuation?.resume()
        firstAttemptStartedContinuation = nil
        guard !didSignalOverlappingRequest else { return }
        await withCheckedContinuation { continuation in
            overlappingRequestContinuation = continuation
        }
    }

    func waitUntilFirstAttemptStarts() async {
        guard !didStartFirstAttempt else { return }
        await withCheckedContinuation { continuation in
            firstAttemptStartedContinuation = continuation
        }
    }

    func signalOverlappingRequest() {
        didSignalOverlappingRequest = true
        overlappingRequestContinuation?.resume()
        overlappingRequestContinuation = nil
    }
}

@MainActor
private final class DeferredThenSuccessfulWriteExecutor: WriteQueueExecutor {
    private let barrier: OverlappingDrainBarrier
    private(set) var attemptedIds: [UUID] = []
    private(set) var successfulIds: [UUID] = []

    init(barrier: OverlappingDrainBarrier) {
        self.barrier = barrier
    }

    func execute(write: PendingWriteRecord) async throws {
        attemptedIds.append(write.id)
        if attemptedIds.count == 1 {
            await barrier.suspendFirstAttemptUntilOverlap()
            throw WriteQueueError.accountAuthorizationUnavailable
        }
        successfulIds.append(write.id)
    }
}

private final class CancellingAfterSuccessWriteExecutor: WriteQueueExecutor {
    private(set) var executedIds: [UUID] = []

    func execute(write: PendingWriteRecord) async throws {
        executedIds.append(write.id)
        withUnsafeCurrentTask { task in
            task?.cancel()
        }
    }
}

private final class WriteQueueSleepProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [CheckedContinuation<Void, Error>] = []
    private(set) var sleepCallCount = 0

    func sleep(nanoseconds: UInt64) async throws {
        _ = nanoseconds
        lock.lock()
        sleepCallCount += 1
        lock.unlock()
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            continuations.append(continuation)
            lock.unlock()
        }
    }

    func failSleepsWithCancellation() {
        lock.lock()
        let continuations = continuations
        self.continuations = []
        lock.unlock()
        for continuation in continuations {
            continuation.resume(throwing: CancellationError())
        }
    }
}

private enum MockError: Error {
    case forced
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
        if condition() {
            return
        }
        await Task.yield()
    }

    let isSatisfied = condition()
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
