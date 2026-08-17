import Foundation
import OSLog

enum WriteQueueProcessingWaitOutcome {
    case finished
    case takeOwnership
}

@MainActor
final class WriteQueueProcessingState {
    var fullDrainRequested = false
    var waiters: [CheckedContinuation<WriteQueueProcessingWaitOutcome, Never>] = []
}

@MainActor
extension WriteQueue {
    func processQueue() async {
        guard executor != nil, canAttemptServerWrite else { return }
        if isProcessing {
            processingState.fullDrainRequested = true
            let outcome = await waitForProcessingToFinish()
            if outcome == .takeOwnership {
                await processFullDrainAsOwner()
            }
            return
        }

        isProcessing = true
        await processFullDrainAsOwner()
    }

    func processRetriedWrite(id: UUID) async {
        guard !isProcessing, executor != nil, canAttemptServerWrite else { return }

        isProcessing = true
        var wasCancelled = false
        do {
            if let fetchedWrite = try await fetchPendingWrite(id: id) {
                _ = try await processWrite(fetchedWrite)
            }
        } catch is CancellationError {
            wasCancelled = Task.isCancelled
            logger.info("Retried write processing cancelled")
        } catch {
            logger.error("Failed to process retried write: \(error.localizedDescription, privacy: .public)")
        }

        await loadQueueCounts()
        guard shouldRunRequestedFullDrain else {
            finishProcessing()
            return
        }
        if wasCancelled, handOffProcessingOwnership() {
            return
        }
        await processFullDrainAsOwner()
    }

    private func waitForProcessingToFinish() async -> WriteQueueProcessingWaitOutcome {
        await withCheckedContinuation { continuation in
            processingState.waiters.append(continuation)
        }
    }

    private func processFullDrainAsOwner() async {
        repeat {
            processingState.fullDrainRequested = false
            var wasCancelled = false
            do {
                try await processQueueUntilDrained()
            } catch is CancellationError {
                wasCancelled = Task.isCancelled
                logger.info("Write queue processing cancelled")
            } catch {
                logger.error("Write queue processing failed: \(error.localizedDescription, privacy: .public)")
            }

            await loadQueueCounts()
            if wasCancelled, shouldHandOffCancelledDrain, handOffProcessingOwnership() {
                return
            }
        } while shouldRunRequestedFullDrain

        finishProcessing()
    }

    private var shouldRunRequestedFullDrain: Bool {
        processingState.fullDrainRequested
            && activePendingCount > 0
            && canAttemptServerWrite
    }

    private var shouldHandOffCancelledDrain: Bool {
        !processingState.waiters.isEmpty
            && activePendingCount > 0
            && canAttemptServerWrite
    }

    private func handOffProcessingOwnership() -> Bool {
        guard !processingState.waiters.isEmpty else { return false }
        processingState.fullDrainRequested = false
        processingState.waiters.removeFirst().resume(returning: .takeOwnership)
        return true
    }

    private func finishProcessing() {
        isProcessing = false
        processingState.fullDrainRequested = false
        let waiters = processingState.waiters
        processingState.waiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: .finished)
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
}
