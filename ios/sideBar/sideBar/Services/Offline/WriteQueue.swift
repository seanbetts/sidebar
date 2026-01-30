import Combine
import CoreData
import Foundation

enum WriteOperation: String {
    case create
    case update
    case delete
    case rename
    case pin
    case archive
    case move
    case copy
}

enum WriteEntityType: String, Codable {
    case note
    case task
    case message
    case website
    case file
    case scratchpad
}

enum WriteQueueStatus: String {
    case pending
    case inProgress
    case failed
}

struct PendingWriteSummary: Identifiable {
    let id: UUID
    let operationType: String
    let entityType: String
    let entityId: String?
    let status: String
    let attempts: Int16
    let lastError: String?
    let conflictReason: String?
    let createdAt: Date
    let lastAttemptAt: Date?
}

struct PendingWriteRecord: Sendable, Equatable {
    let id: UUID
    let operationType: String
    let entityType: String
    let entityId: String?
    let payload: Data
    let serverSnapshot: Data?
    let attempts: Int16
}

enum WriteQueueError: Error {
    case missingExecutor
    case missingQueue
    case queueFull
}

struct WriteQueueConflictError: Error {
    let reason: String
    let serverSnapshot: Data?
}

enum WriteQueueConflictResolution {
    case keepLocal
    case keepServer
}

@MainActor
protocol WriteQueueExecutor {
    func execute(write: PendingWriteRecord) async throws
}

@MainActor
/// Queues offline write operations and retries them when online.
public final class WriteQueue: ObservableObject {
    @Published private(set) var pendingCount: Int = 0
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var isPausedForConflict: Bool = false
    public let maxPendingWrites: Int

    private let container: NSPersistentContainer
    private let connectivityMonitor: ConnectivityMonitor
    private let executor: WriteQueueExecutor?
    private let autoProcessEnabled: Bool
    private var cancellables = Set<AnyCancellable>()
    private let encoder = JSONEncoder()

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
            await self?.loadPendingCount()
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

        let currentCount = try await countPendingWrites()
        if currentCount >= maxPendingWrites {
            throw WriteQueueError.queueFull
        }

        try await performBackgroundTask { context in
            let write = PendingWrite(context: context)
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
        guard !isProcessing, !isPausedForConflict, executor != nil, !connectivityMonitor.isOffline else { return }
        isProcessing = true
        defer { isProcessing = false }

        while let write = try? await fetchNextPending() {
            let shouldContinue = await processWrite(write)
            if !shouldContinue {
                break
            }
            await Task.yield()
        }

        await loadPendingCount()
    }

    func fetchPendingWrites() async -> [PendingWriteSummary] {
        do {
            return try await performBackgroundTask { context in
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
        } catch {
            return []
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
            return
        }
    }

    public func resumeProcessing() {
        isPausedForConflict = false
        Task { [weak self] in
            await self?.processQueue()
        }
    }

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
                    if write.entityType == WriteEntityType.task.rawValue,
                       let rebasedPayload = rebaseTaskPayload(
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
            return
        }
        await loadPendingCount()
        resumeProcessing()
    }

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
                await markWriteFailed(
                    id: write.id,
                    error: conflictError,
                    shouldRetry: false,
                    conflictReason: conflictError.reason,
                    serverSnapshot: conflictError.serverSnapshot
                )
                isPausedForConflict = true
                return false
            }
            let shouldRetry = shouldRetry(attempts: write.attempts)
            await markWriteFailed(id: write.id, error: error, shouldRetry: shouldRetry)
            if shouldRetry {
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
                if let conflictReason {
                    write.conflictReason = conflictReason
                }
                if let serverSnapshot {
                    write.serverSnapshot = serverSnapshot
                }
            }
        } catch {
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
            pendingCount = 0
        }
    }

    private func observeNetwork() {
        connectivityMonitor.$isOffline
            .removeDuplicates()
            .filter { !$0 }
            .sink { [weak self] _ in
                guard let self, self.autoProcessEnabled, !self.isPausedForConflict else { return }
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

    private func rebaseTaskPayload(payloadData: Data, serverSnapshot: Data?) -> Data? {
        guard let serverSnapshot else { return nil }
        let decoder = JSONDecoder()
        guard let conflict = try? decoder.decode(TaskSyncConflict.self, from: serverSnapshot),
              let serverUpdatedAt = conflict.serverUpdatedAt,
              let payload = try? decoder.decode(TaskOperationPayload.self, from: payloadData) else {
            return nil
        }
        let rebased = TaskOperationPayload(
            operationId: payload.operationId,
            op: payload.op,
            id: payload.id,
            title: payload.title,
            notes: payload.notes,
            listId: payload.listId,
            dueDate: payload.dueDate,
            startDate: payload.startDate,
            recurrenceRule: payload.recurrenceRule,
            clientUpdatedAt: serverUpdatedAt
        )
        return try? encoder.encode(rebased)
    }

    private func performBackgroundTask<T>(
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
}
