// swiftlint:disable file_length
import Combine
import CoreData
import Foundation
import OSLog
@MainActor
/// Queues offline write operations and retries them when online.
public final class WriteQueue: ObservableObject {
    @Published private(set) var pendingCount: Int = 0
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var isPausedForConflict: Bool = false
    public let maxPendingWrites: Int
    let container: NSPersistentContainer
    private let connectivityMonitor: ConnectivityMonitor
    private let executor: WriteQueueExecutor?
    private let autoProcessEnabled: Bool
    private var cancellables = Set<AnyCancellable>()
    private let encoder = JSONEncoder()
    let logger = Logger(subsystem: "sideBar", category: "WriteQueue")
    var hasRecoveredStuckWrites = false
    var hasRecoveredConflictWrites = false
    init(
        container: NSPersistentContainer,
        connectivityMonitor: ConnectivityMonitor,
        executor: WriteQueueExecutor? = nil,
        autoProcessEnabled: Bool = true,
        maxPendingWrites: Int = 200
    ) {
        self.container = container
        self.connectivityMonitor = connectivityMonitor
        self.executor = executor
        self.autoProcessEnabled = autoProcessEnabled
        self.maxPendingWrites = maxPendingWrites
        Task { [weak self] in
            await self?.recoverStuckWritesIfNeeded()
            await self?.recoverConflictWritesIfNeeded()
            await self?.loadPendingCount()
            if let self, self.autoProcessEnabled, self.executor != nil, !self.connectivityMonitor.isOffline {
                await self.processQueue()
            }
        }
        observeNetwork()
    }

    func enqueue<T: Encodable>(
        operation: WriteOperation,
        entityType: WriteEntityType,
        entityId: String?,
        payload: T,
        serverSnapshot: ServerSnapshot? = nil
    ) async throws {
        let payloadData = try encoder.encode(payload)
        let snapshotData = try? encodeSnapshot(serverSnapshot)
        if operation == .update,
           entityType == .note,
           let entityId,
           try await coalesceNoteUpdate(entityId: entityId, payload: payloadData) {
            await loadPendingCount()
            if autoProcessEnabled, executor != nil, !connectivityMonitor.isOffline {
                Task { [weak self] in
                    await self?.processQueue()
                }
            }
            return
        }
        if operation == .update, entityType == .task, let entityId,
           try await coalesceTaskNotesUpdate(entityId: entityId, payload: payloadData) {
            await loadPendingCount()
            if autoProcessEnabled, executor != nil, !connectivityMonitor.isOffline {
                Task { [weak self] in
                    await self?.processQueue()
                }
            }
            return
        }

        let currentCount = try await countPendingWrites()
        if currentCount >= maxPendingWrites {
            throw WriteQueueError.queueFull
        }

        try await performBackgroundTask { context in
            let write = PendingWrite.insertNew(in: context)
            write.id = UUID()
            write.operationType = operation.rawValue
            write.entityType = entityType.rawValue
            write.entityId = entityId
            write.payload = payloadData
            write.createdAt = Date()
            write.attempts = 0
            write.status = WriteQueueStatus.pending.rawValue
            write.serverSnapshot = snapshotData
        }

        await loadPendingCount()

        if autoProcessEnabled, executor != nil, !connectivityMonitor.isOffline {
            Task { [weak self] in
                await self?.processQueue()
            }
        }
    }

    func processQueue() async {
        guard !isProcessing, executor != nil, !connectivityMonitor.isOffline else { return }
        await recoverStuckWritesIfNeeded()
        await recoverConflictWritesIfNeeded()
        isProcessing = true
        defer { isProcessing = false }

        while true {
            let write: PendingWriteRecord?
            do {
                write = try await fetchNextPending()
            } catch {
                logger.error("Failed to fetch next pending write: \(error.localizedDescription, privacy: .public)")
                break
            }
            guard let write else {
                break
            }
            let shouldContinue = await processWrite(write)
            if !shouldContinue {
                break
            }
            await Task.yield()
        }

        await loadPendingCount()
    }

    func fetchPendingWrites() async throws -> [PendingWriteSummary] {
        try await performBackgroundTask { context in
            let request = PendingWrite.fetchRequest()
            request.sortDescriptors = [
                NSSortDescriptor(keyPath: \PendingWrite.createdAt, ascending: false)
            ]
            let writes = try context.fetch(request)
            return writes.map { write in
                PendingWriteSummary(
                    id: write.id,
                    operationType: write.operationType,
                    entityType: write.entityType,
                    entityId: write.entityId,
                    status: write.status,
                    attempts: write.attempts,
                    lastError: write.lastError,
                    conflictReason: write.conflictReason,
                    createdAt: write.createdAt,
                    lastAttemptAt: write.lastAttemptAt
                )
            }
        }
    }

    func hasPendingWritesNeedingFlush() async -> Bool {
        do {
            return try await performBackgroundTask { context in
                let request = PendingWrite.fetchRequest()
                request.fetchLimit = 1
                request.predicate = NSPredicate(
                    format: "status == %@ OR status == %@",
                    WriteQueueStatus.pending.rawValue,
                    WriteQueueStatus.inProgress.rawValue
                )
                return try context.fetch(request).isEmpty == false
            }
        } catch {
            logger.error("Failed to inspect pending writes for background flush: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func fetchNextConflict() async throws -> PendingWriteSummary? {
        try await performBackgroundTask { context in
            let request = PendingWrite.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "conflictReason != nil")
            request.sortDescriptors = [
                NSSortDescriptor(keyPath: \PendingWrite.createdAt, ascending: true)
            ]
            guard let write = try context.fetch(request).first else { return nil }
            return PendingWriteSummary(
                id: write.id,
                operationType: write.operationType,
                entityType: write.entityType,
                entityId: write.entityId,
                status: write.status,
                attempts: write.attempts,
                lastError: write.lastError,
                conflictReason: write.conflictReason,
                createdAt: write.createdAt,
                lastAttemptAt: write.lastAttemptAt
            )
        }
    }

    func deleteWrites(ids: [UUID]) async {
        guard !ids.isEmpty else { return }
        do {
            try await performBackgroundTask { context in
                let request = PendingWrite.fetchRequest()
                request.predicate = NSPredicate(format: "id IN %@", ids)
                let writes = try context.fetch(request)
                writes.forEach { context.delete($0) }
            }
        } catch {
            logger.error("Failed to delete writes by id: \(error.localizedDescription, privacy: .public)")
            return
        }
        await loadPendingCount()
    }

    func deleteWrites(entityType: WriteEntityType, entityId: String) async {
        do {
            try await performBackgroundTask { context in
                let request = PendingWrite.fetchRequest()
                request.predicate = NSPredicate(
                    format: "entityType == %@ AND entityId == %@",
                    entityType.rawValue,
                    entityId
                )
                let writes = try context.fetch(request)
                writes.forEach { context.delete($0) }
            }
        } catch {
            let entity = entityType.rawValue
            let description = error.localizedDescription
            logger.error(
                "Failed to delete writes for entity \(entity, privacy: .public): \(description, privacy: .public)"
            )
            return
        }
        await loadPendingCount()
    }

    public func pruneOldestWrites(keeping maxCount: Int) async {
        guard maxCount >= 0 else { return }
        do {
            try await performBackgroundTask { context in
                let request = PendingWrite.fetchRequest()
                request.predicate = NSPredicate(
                    format: "status == %@ OR status == %@",
                    WriteQueueStatus.pending.rawValue,
                    WriteQueueStatus.failed.rawValue
                )
                request.sortDescriptors = [
                    NSSortDescriptor(keyPath: \PendingWrite.createdAt, ascending: true)
                ]
                let writes = try context.fetch(request)
                guard writes.count > maxCount else { return }
                let deleteCount = writes.count - maxCount
                for write in writes.prefix(deleteCount) {
                    context.delete(write)
                }
            }
            await loadPendingCount()
        } catch {
            logger.error("Failed to prune oldest writes: \(error.localizedDescription, privacy: .public)")
            return
        }
    }

    public func resumeProcessing() {
        isPausedForConflict = false
        Task { [weak self] in
            await self?.processQueue()
        }
    }

    func retryAllWrites() async {
        await retryFailedWrites()
        await processQueue()
        await loadPendingCount()
    }

    func setConflictPauseState(_ isPaused: Bool) { isPausedForConflict = isPaused }
    func resolveConflict(id: UUID, resolution: WriteQueueConflictResolution) async {
        do {
            try await performBackgroundTask { context in
                let request = PendingWrite.fetchRequest()
                request.fetchLimit = 1
                request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                guard let write = try context.fetch(request).first else { return }
                switch resolution {
                case .keepServer:
                    context.delete(write)
                case .keepLocal:
                    if let rebasedPayload = rebaseConflictPayload(
                        entityType: write.entityType,
                        payloadData: write.payload,
                        serverSnapshot: write.serverSnapshot
                    ) {
                        write.payload = rebasedPayload
                    }
                    write.status = WriteQueueStatus.pending.rawValue
                    write.attempts = 0
                    write.lastError = nil
                    write.lastAttemptAt = nil
                    write.conflictReason = nil
                    write.serverSnapshot = nil
                }
            }
        } catch {
            logger.error("Failed to resolve write conflict: \(error.localizedDescription, privacy: .public)")
            return
        }
        await loadPendingCount()
        resumeProcessing()
    }
}

private extension WriteQueue {
    // MARK: - Private

    private func processWrite(_ write: PendingWriteRecord) async -> Bool {
        do {
            guard let executor else {
                throw WriteQueueError.missingExecutor
            }
            try await executor.execute(write: write)
            try await deleteWrite(id: write.id)
            return true
        } catch {
            if let conflictError = error as? WriteQueueConflictError {
                await autoResolveConflict(write: write, error: conflictError)
                return true
            }
            let shouldRetryWrite: Bool
            if case .unknownEntityType = (error as? WriteQueueError) {
                shouldRetryWrite = false
            } else {
                shouldRetryWrite = shouldRetry(attempts: write.attempts)
            }
            await markWriteFailed(id: write.id, error: error, shouldRetry: shouldRetryWrite)
            if shouldRetryWrite {
                let delay = backoffDelay(for: Int(write.attempts))
                try? await Task.sleep(nanoseconds: delay)
            }
            return true
        }
    }

    private func shouldRetry(attempts: Int16) -> Bool {
        attempts < 5
    }

    private func backoffDelay(for attempt: Int) -> UInt64 {
        let seconds = min(pow(2.0, Double(max(attempt - 1, 0))), 16.0)
        return UInt64(seconds * 1_000_000_000)
    }

    private func fetchNextPending() async throws -> PendingWriteRecord? {
        try await performBackgroundTask { context in
            let request = PendingWrite.fetchRequest()
            request.predicate = NSPredicate(format: "status == %@", WriteQueueStatus.pending.rawValue)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \PendingWrite.createdAt, ascending: true)]
            request.fetchLimit = 1
            guard let write = try context.fetch(request).first else {
                return nil
            }
            write.status = WriteQueueStatus.inProgress.rawValue
            write.attempts += 1
            write.lastAttemptAt = Date()
            return PendingWriteRecord(
                id: write.id,
                operationType: write.operationType,
                entityType: write.entityType,
                entityId: write.entityId,
                payload: write.payload,
                serverSnapshot: write.serverSnapshot,
                attempts: write.attempts
            )
        }
    }

    private func coalesceNoteUpdate(entityId: String, payload: Data) async throws -> Bool {
        try await performBackgroundTask { context in
            let request = PendingWrite.fetchRequest()
            request.predicate = NSPredicate(
                format: "operationType == %@ AND entityType == %@ AND entityId == %@ AND (status == %@ OR status == %@)",
                WriteOperation.update.rawValue,
                WriteEntityType.note.rawValue,
                entityId,
                WriteQueueStatus.pending.rawValue,
                WriteQueueStatus.failed.rawValue
            )
            request.sortDescriptors = [NSSortDescriptor(keyPath: \PendingWrite.createdAt, ascending: false)]
            request.fetchLimit = 1
            guard let write = try context.fetch(request).first else {
                return false
            }
            write.payload = payload
            write.createdAt = Date()
            write.status = WriteQueueStatus.pending.rawValue
            write.attempts = 0
            write.lastError = nil
            write.lastAttemptAt = nil
            return true
        }
    }

    private func coalesceTaskNotesUpdate(entityId: String, payload: Data) async throws -> Bool {
        let decoder = JSONDecoder()
        guard let incoming = try? decoder.decode(TaskOperationPayload.self, from: payload),
              incoming.op.lowercased() == "notes" else { return false }
        return try await performBackgroundTask { context in
            let request = PendingWrite.fetchRequest()
            request.predicate = NSPredicate(
                format: "operationType == %@ AND entityType == %@ AND entityId == %@ AND (status == %@ OR status == %@)",
                WriteOperation.update.rawValue, WriteEntityType.task.rawValue, entityId,
                WriteQueueStatus.pending.rawValue, WriteQueueStatus.failed.rawValue
            )
            request.sortDescriptors = [NSSortDescriptor(keyPath: \PendingWrite.createdAt, ascending: false)]
            request.fetchLimit = 1
            guard let write = try context.fetch(request).first,
                  let existing = try? decoder.decode(TaskOperationPayload.self, from: write.payload),
                  existing.op.lowercased() == "notes" else { return false }
            write.payload = payload; write.createdAt = Date(); write.status = WriteQueueStatus.pending.rawValue
            write.attempts = 0; write.lastError = nil; write.lastAttemptAt = nil
            return true
        }
    }

    private func retryFailedWrites() async {
        do {
            try await performBackgroundTask { context in
                let request = PendingWrite.fetchRequest()
                request.predicate = NSPredicate(format: "status == %@", WriteQueueStatus.failed.rawValue)
                let writes = try context.fetch(request)
                for write in writes {
                    write.status = WriteQueueStatus.pending.rawValue
                    write.lastError = nil
                    write.lastAttemptAt = nil
                    write.conflictReason = nil
                    write.serverSnapshot = nil
                }
            }
        } catch {
            logger.error("Failed to retry failed writes: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func markWriteFailed(
        id: UUID,
        error: Error,
        shouldRetry: Bool,
        conflictReason: String? = nil,
        serverSnapshot: Data? = nil
    ) async {
        do {
            try await performBackgroundTask { context in
                let request = PendingWrite.fetchRequest()
                request.fetchLimit = 1
                request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                guard let write = try context.fetch(request).first else { return }
                write.status = shouldRetry ? WriteQueueStatus.pending.rawValue : WriteQueueStatus.failed.rawValue
                write.lastError = String(describing: error)
                write.conflictReason = conflictReason
                write.serverSnapshot = serverSnapshot
            }
        } catch {
            logger.error("Failed to mark write as failed: \(error.localizedDescription, privacy: .public)")
            return
        }
    }

    private func deleteWrite(id: UUID) async throws {
        try await performBackgroundTask { context in
            let request = PendingWrite.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            guard let write = try context.fetch(request).first else { return }
            context.delete(write)
        }
    }

    private func countPendingWrites() async throws -> Int {
        try await performBackgroundTask { context in
            let request = PendingWrite.fetchRequest()
            request.predicate = NSPredicate(
                format: "status == %@ OR status == %@",
                WriteQueueStatus.pending.rawValue,
                WriteQueueStatus.failed.rawValue
            )
            return try context.count(for: request)
        }
    }

    private func loadPendingCount() async {
        do {
            pendingCount = try await countPendingWrites()
        } catch {
            logger.error("Failed to load pending count: \(error.localizedDescription, privacy: .public)")
            pendingCount = 0
        }
    }

    private func observeNetwork() {
        connectivityMonitor.$isOffline
            .removeDuplicates()
            .filter { !$0 }
            .sink { [weak self] _ in
                guard let self, self.autoProcessEnabled else { return }
                Task { [weak self] in
                    await self?.processQueue()
                }
            }
            .store(in: &cancellables)
    }

    private func encodeSnapshot(_ snapshot: ServerSnapshot?) throws -> Data? {
        guard let snapshot else { return nil }
        return try encoder.encode(snapshot)
    }

    func performBackgroundTask<T>(
        _ work: @escaping (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            container.performBackgroundTask { context in
                context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                do {
                    let result = try work(context)
                    if context.hasChanges {
                        try context.save()
                    }
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func autoResolveConflict(write: PendingWriteRecord, error: WriteQueueConflictError) async {
        let rebasedPayload = rebaseConflictPayload(
            entityType: write.entityType,
            payloadData: write.payload,
            serverSnapshot: error.serverSnapshot ?? write.serverSnapshot
        )

        do {
            try await performBackgroundTask { context in
                let request = PendingWrite.fetchRequest()
                request.fetchLimit = 1
                request.predicate = NSPredicate(format: "id == %@", write.id as CVarArg)
                guard let pendingWrite = try context.fetch(request).first else { return }
                if let rebasedPayload {
                    pendingWrite.payload = rebasedPayload
                    pendingWrite.status = WriteQueueStatus.pending.rawValue
                    pendingWrite.attempts = 0
                    pendingWrite.lastError = nil
                    pendingWrite.lastAttemptAt = nil
                } else {
                    pendingWrite.status = WriteQueueStatus.failed.rawValue
                    pendingWrite.lastError = "Automatic conflict resolution failed: \(error.reason)"
                }
                pendingWrite.conflictReason = nil
                pendingWrite.serverSnapshot = nil
            }
        } catch {
            logger.error("Failed to auto-resolve write conflict: \(error.localizedDescription, privacy: .public)")
        }
    }
}
