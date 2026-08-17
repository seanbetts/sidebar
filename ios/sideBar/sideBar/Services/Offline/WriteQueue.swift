import Combine
import CoreData
import Foundation
import OSLog
/// Queues offline write operations and retries them when online.
@MainActor public final class WriteQueue: ObservableObject {
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
    private var processAgainAfterCurrentPass = false
    private var processingWaiters: [CheckedContinuation<Void, Never>] = []
    private var isQueueDrainProcessing = false
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
        retrySleep: WriteQueueSleep? = nil
    ) {
        self.container = container
        self.connectivityMonitor = connectivityMonitor
        self.executor = executor
        self.autoProcessEnabled = autoProcessEnabled
        self.maxPendingWrites = maxPendingWrites
        self.retrySleep = retrySleep ?? WriteQueueSleepFactory.live
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
        serverSnapshot: ServerSnapshot? = nil,
        writeId: UUID = UUID()
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
            write.id = writeId
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
        guard executor != nil, canAttemptServerWrite else { return }
        if isProcessing {
            guard isQueueDrainProcessing else { return }
            processAgainAfterCurrentPass = true
            await waitForProcessingToFinish()
            return
        }
        isProcessing = true
        isQueueDrainProcessing = true
        defer { finishProcessing() }
        repeat {
            processAgainAfterCurrentPass = false
            do {
                try await processQueueUntilDrained()
            } catch is CancellationError {
                logger.info("Write queue processing cancelled")
            } catch {
                logger.error("Write queue processing failed: \(error.localizedDescription, privacy: .public)")
            }

            await loadQueueCounts()
        } while processAgainAfterCurrentPass
            && activePendingCount > 0
            && canAttemptServerWrite
    }

    private func waitForProcessingToFinish() async {
        await withCheckedContinuation { continuation in
            processingWaiters.append(continuation)
        }
    }

    private func finishProcessing() {
        isProcessing = false
        isQueueDrainProcessing = false
        let waiters = processingWaiters
        processingWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
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
                await restoreFetchedWriteState(
                    fetchedWrite,
                    restoreAttemptState: fetchedWrite.restoresOriginalAttemptState
                )
            }
            throw CancellationError()
        } catch WriteQueueError.accountAuthorizationUnavailable {
            await restoreFetchedWriteState(fetchedWrite, restoreAttemptState: true)
            return false
        } catch WriteQueueError.accountScopeChanged {
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
                shouldRetryWrite = WriteQueueRetryPolicy.shouldRetry(attempts: write.attempts)
            }
            await markWriteFailed(id: write.id, error: error, shouldRetry: shouldRetryWrite)
            if shouldRetryWrite {
                let delay = WriteQueueRetryPolicy.backoffDelayNanoseconds(forAttempt: Int(write.attempts))
                do {
                    try await retrySleep(delay)
                } catch is CancellationError {
                    await restoreFetchedWriteState(
                        fetchedWrite,
                        restoreAttemptState: fetchedWrite.restoresOriginalAttemptState
                    )
                    throw CancellationError()
                }
            }
            return true
        }
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
                record: PendingWriteQueueMapper.record(from: write),
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
                record: PendingWriteQueueMapper.record(from: write),
                recoveryState: originalState,
                restoresOriginalAttemptState: true
            )
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

    private func restoreFetchedWriteState(_ fetchedWrite: FetchedPendingWrite, restoreAttemptState: Bool) async {
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
                if restoreAttemptState {
                    write.attempts = fetchedWrite.recoveryState.attempts
                    write.lastAttemptAt = fetchedWrite.recoveryState.lastAttemptAt
                }
            }
        } catch {
            logger.error("Failed to restore fetched write state: \(error.localizedDescription, privacy: .public)")
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
                for write in writes where WriteQueueRetryPolicy.shouldReplayFailedWrite(
                    lastError: write.lastError,
                    conflictReason: write.conflictReason
                ) {
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
}
