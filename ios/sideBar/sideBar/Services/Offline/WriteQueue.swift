// swiftlint:disable file_length
import Combine
import CoreData
import Foundation
import OSLog
@MainActor
/// Queues offline write operations and retries them when online.
public final class WriteQueue: ObservableObject {
    @Published private(set) var pendingCount: Int = 0
    @Published private(set) var failedCount: Int = 0
    @Published private(set) var failedHeaderRows: [PendingWriteSummary] = []
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var isExecutingWrite: Bool = false
    @Published private(set) var isPausedForConflict: Bool = false
    public let maxPendingWrites: Int
    let container: NSPersistentContainer
    private let connectivityMonitor: ConnectivityMonitor
    private let executor: WriteQueueExecutor?
    private let autoProcessEnabled: Bool
    private let retrySleep: WriteQueueSleep
    private var cancellables = Set<AnyCancellable>()
    private let encoder = JSONEncoder()
    let logger = Logger(subsystem: "sideBar", category: "WriteQueue")
    var hasRecoveredStuckWrites = false
    var hasRecoveredConflictWrites = false

    var activePendingCount: Int {
        max(pendingCount - failedCount, 0)
    }

    private var canAttemptServerWrite: Bool {
        connectivityMonitor.offlineCapabilityPolicy.canAttemptServerWrite
    }

    func applyHeaderQueueState(
        pendingCount: Int,
        failedCount: Int,
        failedHeaderRows: [PendingWriteSummary]
    ) {
        self.pendingCount = pendingCount
        self.failedCount = failedCount
        self.failedHeaderRows = failedHeaderRows
    }

    init(
        container: NSPersistentContainer,
        connectivityMonitor: ConnectivityMonitor,
        executor: WriteQueueExecutor? = nil,
        autoProcessEnabled: Bool = true,
        maxPendingWrites: Int = 200,
        retrySleep: @escaping WriteQueueSleep = WriteQueueSleepFactory.live
    ) {
        self.container = container
        self.connectivityMonitor = connectivityMonitor
        self.executor = executor
        self.autoProcessEnabled = autoProcessEnabled
        self.maxPendingWrites = maxPendingWrites
        self.retrySleep = retrySleep
        Task { [weak self] in
            await self?.startupRecoveryAndProcessing()
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
            await loadQueueCounts()
            if autoProcessEnabled, executor != nil, canAttemptServerWrite {
                Task { [weak self] in
                    await self?.processQueue()
                }
            }
            return
        }
        if operation == .update, entityType == .task, let entityId,
           try await coalesceTaskNotesUpdate(entityId: entityId, payload: payloadData) {
            await loadQueueCounts()
            if autoProcessEnabled, executor != nil, canAttemptServerWrite {
                Task { [weak self] in
                    await self?.processQueue()
                }
            }
            return
        }
        if operation == .update, entityType == .settings,
           try await coalesceSettingsUpdate(payload: payloadData) {
            await loadQueueCounts()
            if autoProcessEnabled, executor != nil, canAttemptServerWrite {
                Task { [weak self] in
                    await self?.processQueue()
                }
            }
            return
        }

        let currentCount = try await countQueuedWrites()
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

        await loadQueueCounts()

        if autoProcessEnabled, executor != nil, canAttemptServerWrite {
            Task { [weak self] in
                await self?.processQueue()
            }
        }
    }

    func processQueue() async {
        guard !isProcessing, executor != nil, canAttemptServerWrite else { return }
        isProcessing = true
        defer { isProcessing = false }

        do {
            try await processQueueUntilDrained()
        } catch is CancellationError {
            logger.info("Write queue processing cancelled")
        } catch {
            logger.error("Write queue processing failed: \(error.localizedDescription, privacy: .public)")
        }

        await loadQueueCounts()
    }

    private func startupRecoveryAndProcessing() async {
        do {
            try Task.checkCancellation()
            await recoverStuckWritesIfNeeded()
            try Task.checkCancellation()
            await recoverConflictWritesIfNeeded()
            try Task.checkCancellation()
            await loadQueueCounts()
            if autoProcessEnabled, executor != nil, canAttemptServerWrite {
                await processQueue()
            }
        } catch is CancellationError {
            return
        } catch {
            logger.error("Write queue startup recovery failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func processQueueUntilDrained() async throws {
        try Task.checkCancellation()
        await recoverStuckWritesIfNeeded()
        try Task.checkCancellation()
        await recoverConflictWritesIfNeeded()
        try Task.checkCancellation()
        await recoverRetryableFailedWrites()

        while true {
            try Task.checkCancellation()
            let fetchedWrite = try await fetchNextPending()
            guard let fetchedWrite else {
                break
            }
            let shouldContinue = try await processWrite(fetchedWrite)
            if !shouldContinue {
                break
            }
            await Task.yield()
        }
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
        await loadQueueCounts()
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
        await loadQueueCounts()
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
            await loadQueueCounts()
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
        await loadQueueCounts()
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
        await loadQueueCounts()
        resumeProcessing()
    }

    func processRetriedWrite(id: UUID) async {
        guard !isProcessing, executor != nil, canAttemptServerWrite else { return }

        isProcessing = true
        defer { isProcessing = false }

        do {
            guard let fetchedWrite = try await fetchPendingWrite(id: id) else {
                await loadQueueCounts()
                return
            }
            _ = try await processWrite(fetchedWrite)
        } catch is CancellationError {
            logger.info("Retried write processing cancelled")
        } catch {
            logger.error("Failed to process retried write: \(error.localizedDescription, privacy: .public)")
        }

        await loadQueueCounts()
    }
}

extension WriteQueue: SettingsWriteQueueEnqueuing {}

private struct FetchedPendingWrite: Sendable {
    let record: PendingWriteRecord
    let recoveryState: PendingWriteRecoveryState
    let restoresOriginalAttemptState: Bool
}

private struct PendingWriteRecoveryState: Sendable {
    let status: String
    let attempts: Int16
    let lastAttemptAt: Date?
    let lastError: String?
    let conflictReason: String?
    let serverSnapshot: Data?
}

extension WriteQueue {
    // MARK: - Private

    private func processWrite(_ fetchedWrite: FetchedPendingWrite) async throws -> Bool {
        let write = fetchedWrite.record
        var didExecuteWrite = false
        do {
            try Task.checkCancellation()
            guard let executor else {
                throw WriteQueueError.missingExecutor
            }
            isExecutingWrite = true
            defer { isExecutingWrite = false }
            try await executor.execute(write: write)
            didExecuteWrite = true
            try await deleteWrite(id: write.id)
            return true
        } catch is CancellationError {
            if !didExecuteWrite {
                await restoreFetchedWriteAfterCancellation(fetchedWrite)
            }
            throw CancellationError()
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
                do {
                    try await retrySleep(delay)
                } catch is CancellationError {
                    await restoreFetchedWriteAfterCancellation(fetchedWrite)
                    throw CancellationError()
                }
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

    private func fetchNextPending() async throws -> FetchedPendingWrite? {
        try await performBackgroundTask { context in
            let request = PendingWrite.fetchRequest()
            request.predicate = NSPredicate(format: "status == %@", WriteQueueStatus.pending.rawValue)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \PendingWrite.createdAt, ascending: true)]
            request.fetchLimit = 1
            guard let write = try context.fetch(request).first else {
                return nil
            }
            let originalState = PendingWriteRecoveryState(
                status: write.status,
                attempts: write.attempts,
                lastAttemptAt: write.lastAttemptAt,
                lastError: write.lastError,
                conflictReason: write.conflictReason,
                serverSnapshot: write.serverSnapshot
            )
            write.status = WriteQueueStatus.inProgress.rawValue
            write.attempts += 1
            write.lastAttemptAt = Date()
            return FetchedPendingWrite(
                record: PendingWriteRecord(
                    id: write.id,
                    operationType: write.operationType,
                    entityType: write.entityType,
                    entityId: write.entityId,
                    payload: write.payload,
                    serverSnapshot: write.serverSnapshot,
                    attempts: write.attempts
                ),
                recoveryState: originalState,
                restoresOriginalAttemptState: false
            )
        }
    }

    private func fetchPendingWrite(id: UUID) async throws -> FetchedPendingWrite? {
        try await performBackgroundTask { context in
            let request = PendingWrite.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(
                format: "id == %@ AND status == %@",
                id as CVarArg,
                WriteQueueStatus.pending.rawValue
            )
            guard let write = try context.fetch(request).first else {
                return nil
            }
            let originalState = PendingWriteRecoveryState(
                status: write.status,
                attempts: write.attempts,
                lastAttemptAt: write.lastAttemptAt,
                lastError: write.lastError,
                conflictReason: write.conflictReason,
                serverSnapshot: write.serverSnapshot
            )
            write.status = WriteQueueStatus.inProgress.rawValue
            write.attempts += 1
            write.lastAttemptAt = Date()
            return FetchedPendingWrite(
                record: PendingWriteRecord(
                    id: write.id,
                    operationType: write.operationType,
                    entityType: write.entityType,
                    entityId: write.entityId,
                    payload: write.payload,
                    serverSnapshot: write.serverSnapshot,
                    attempts: write.attempts
                ),
                recoveryState: originalState,
                restoresOriginalAttemptState: true
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

    private func coalesceSettingsUpdate(payload: Data) async throws -> Bool {
        let decoder = JSONDecoder()
        guard let incoming = try? decoder.decode(SettingsMutationPayload.self, from: payload),
              incoming.kind == .settingsPatch else { return false }
        return try await performBackgroundTask { context in
            let request = PendingWrite.fetchRequest()
            request.predicate = NSPredicate(
                format: "operationType == %@ AND entityType == %@ AND entityId == %@ AND (status == %@ OR status == %@)",
                WriteOperation.update.rawValue,
                WriteEntityType.settings.rawValue,
                incoming.entityId,
                WriteQueueStatus.pending.rawValue,
                WriteQueueStatus.failed.rawValue
            )
            request.sortDescriptors = [NSSortDescriptor(keyPath: \PendingWrite.createdAt, ascending: false)]
            request.fetchLimit = 1
            guard let write = try context.fetch(request).first,
                  let existing = try? decoder.decode(SettingsMutationPayload.self, from: write.payload),
                  existing.kind == .settingsPatch else { return false }
            let merged = existing.mergingSettingsPatch(with: incoming)
            write.payload = try JSONEncoder().encode(merged)
            write.createdAt = Date()
            write.status = WriteQueueStatus.pending.rawValue
            write.attempts = 0
            write.lastError = nil
            write.lastAttemptAt = nil
            write.conflictReason = nil
            write.serverSnapshot = nil
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

    private func restoreFetchedWriteAfterCancellation(_ fetchedWrite: FetchedPendingWrite) async {
        do {
            try await performBackgroundTask { context in
                let request = PendingWrite.fetchRequest()
                request.fetchLimit = 1
                request.predicate = NSPredicate(format: "id == %@", fetchedWrite.record.id as CVarArg)
                guard let write = try context.fetch(request).first else { return }
                write.status = fetchedWrite.recoveryState.status
                write.lastError = fetchedWrite.recoveryState.lastError
                write.conflictReason = fetchedWrite.recoveryState.conflictReason
                write.serverSnapshot = fetchedWrite.recoveryState.serverSnapshot
                if fetchedWrite.restoresOriginalAttemptState {
                    write.attempts = fetchedWrite.recoveryState.attempts
                    write.lastAttemptAt = fetchedWrite.recoveryState.lastAttemptAt
                }
            }
        } catch {
            logger.error("Failed to restore cancelled write: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func countQueuedWrites() async throws -> Int {
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

    private func countFailedWrites() async throws -> Int {
        try await performBackgroundTask { context in
            let request = PendingWrite.fetchRequest()
            request.predicate = NSPredicate(format: "status == %@", WriteQueueStatus.failed.rawValue)
            return try context.count(for: request)
        }
    }

    func loadQueueCounts() async {
        do {
            let snapshot = try await performBackgroundTask { context in
                let queuedRequest = PendingWrite.fetchRequest()
                queuedRequest.predicate = NSPredicate(
                    format: "status == %@ OR status == %@",
                    WriteQueueStatus.pending.rawValue,
                    WriteQueueStatus.failed.rawValue
                )

                let failedRequest = PendingWrite.fetchRequest()
                failedRequest.predicate = NSPredicate(format: "status == %@", WriteQueueStatus.failed.rawValue)
                failedRequest.sortDescriptors = [
                    NSSortDescriptor(keyPath: \PendingWrite.createdAt, ascending: true)
                ]

                let pendingCount = try context.count(for: queuedRequest)
                let failedWrites = try context.fetch(failedRequest)
                let failedRows = failedWrites.map { write in
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

                return (pendingCount, failedRows)
            }

            applyHeaderQueueState(
                pendingCount: snapshot.0,
                failedCount: snapshot.1.count,
                failedHeaderRows: snapshot.1
            )
        } catch {
            logger.error("Failed to load queue counts: \(error.localizedDescription, privacy: .public)")
            applyHeaderQueueState(pendingCount: 0, failedCount: 0, failedHeaderRows: [])
        }
    }

    private func observeNetwork() {
        connectivityMonitor.offlineCapabilityPolicyPublisher
            .filter(\.canAttemptServerWrite)
            .sink { [weak self] _ in
                self?.scheduleQueueProcessingIfNeeded()
            }
            .store(in: &cancellables)
    }

    private func scheduleQueueProcessingIfNeeded() {
        guard autoProcessEnabled else { return }
        Task { [weak self] in
            await self?.processQueue()
        }
    }

    private func encodeSnapshot(_ snapshot: ServerSnapshot?) throws -> Data? {
        guard let snapshot else { return nil }
        return try encoder.encode(snapshot)
    }

    private func recoverRetryableFailedWrites() async {
        do {
            let recoveredCount = try await performBackgroundTask { context in
                let request = PendingWrite.fetchRequest()
                request.predicate = NSPredicate(format: "status == %@", WriteQueueStatus.failed.rawValue)
                let writes = try context.fetch(request)
                var recoveredCount = 0
                for write in writes where self.shouldReplayFailedWrite(write) {
                    write.status = WriteQueueStatus.pending.rawValue
                    write.attempts = 0
                    write.lastError = nil
                    write.lastAttemptAt = nil
                    recoveredCount += 1
                }
                return recoveredCount
            }
            if recoveredCount > 0 {
                logger.info("Recovered \(recoveredCount, privacy: .public) retryable failed write(s)")
            }
        } catch {
            logger.error("Failed to recover retryable failed writes: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func shouldReplayFailedWrite(_ write: PendingWrite) -> Bool {
        guard write.conflictReason == nil, let lastError = write.lastError else {
            return false
        }

        if let statusCode = retryableHTTPStatusCode(from: lastError) {
            return statusCode == 408 || statusCode == 429 || statusCode >= 500
        }

        guard let urlErrorCode = urlErrorCode(from: lastError) else {
            return false
        }

        switch urlErrorCode {
        case URLError.notConnectedToInternet.rawValue,
             URLError.networkConnectionLost.rawValue,
             URLError.timedOut.rawValue,
             URLError.cannotFindHost.rawValue,
             URLError.cannotConnectToHost.rawValue,
             URLError.dnsLookupFailed.rawValue:
            return true
        default:
            return false
        }
    }

    private func retryableHTTPStatusCode(from errorDescription: String) -> Int? {
        let prefix = "requestFailed("
        guard let range = errorDescription.range(of: prefix) else {
            return nil
        }
        let suffix = errorDescription[range.upperBound...]
        guard let endIndex = suffix.firstIndex(of: ")") else {
            return nil
        }
        return Int(suffix[..<endIndex])
    }

    private func urlErrorCode(from errorDescription: String) -> Int? {
        let marker = "Code="
        guard errorDescription.contains("NSURLErrorDomain"),
              let codeRange = errorDescription.range(of: marker) else {
            return nil
        }
        let suffix = errorDescription[codeRange.upperBound...]
        let numericPrefix = suffix.prefix { $0 == "-" || $0.isNumber }
        guard !numericPrefix.isEmpty else {
            return nil
        }
        return Int(numericPrefix)
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

private extension SettingsMutationPayload {
    func mergingSettingsPatch(with incoming: SettingsMutationPayload) -> SettingsMutationPayload {
        SettingsMutationPayload(
            communicationStyle: incoming.communicationStyle ?? communicationStyle,
            workingRelationship: incoming.workingRelationship ?? workingRelationship,
            name: incoming.name ?? name,
            jobTitle: incoming.jobTitle ?? jobTitle,
            employer: incoming.employer ?? employer,
            dateOfBirth: incoming.includeDateOfBirth ? incoming.dateOfBirth : dateOfBirth,
            gender: incoming.gender ?? gender,
            pronouns: incoming.pronouns ?? pronouns,
            location: incoming.location ?? location,
            notificationPreferences: incoming.notificationPreferences ?? notificationPreferences,
            assistantIdentity: incoming.assistantIdentity ?? assistantIdentity,
            aiPrimaryProvider: incoming.aiPrimaryProvider ?? aiPrimaryProvider,
            enabledSkills: incoming.enabledSkills ?? enabledSkills,
            includeDateOfBirth: includeDateOfBirth || incoming.includeDateOfBirth
        )
    }
}
