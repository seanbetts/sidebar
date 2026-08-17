import CoreData
import Foundation
@testable import sideBar

@MainActor
final class TargetedRetryBarrier {
    private var didStart = false
    private var didRelease = false
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func suspendTargetedRetry() async {
        didStart = true
        startContinuation?.resume()
        startContinuation = nil
        guard !didRelease else { return }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilTargetedRetryStarts() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }

    func releaseTargetedRetry() {
        didRelease = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@MainActor
final class FullDrainCompletionProbe {
    private(set) var didStart = false
    private(set) var didFinish = false
    private var startContinuation: CheckedContinuation<Void, Never>?

    func markStarted() {
        didStart = true
        startContinuation?.resume()
        startContinuation = nil
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }

    func markFinished() {
        didFinish = true
    }
}

@MainActor
final class TargetedRetryBarrierExecutor: WriteQueueExecutor {
    private let targetedWriteId: UUID
    private let barrier: TargetedRetryBarrier
    private(set) var attemptedIds: [UUID] = []
    private(set) var successfulIds: [UUID] = []

    init(targetedWriteId: UUID, barrier: TargetedRetryBarrier) {
        self.targetedWriteId = targetedWriteId
        self.barrier = barrier
    }

    func execute(write: PendingWriteRecord) async throws {
        attemptedIds.append(write.id)
        if write.id == targetedWriteId {
            await barrier.suspendTargetedRetry()
        }
        successfulIds.append(write.id)
    }
}

@MainActor
func insertFailedLegacyWrite(id: UUID, context: NSManagedObjectContext) throws {
    let write = PendingWrite.insertNew(in: context)
    write.id = id
    write.operationType = WriteOperation.update.rawValue
    write.entityType = WriteEntityType.note.rawValue
    write.entityId = "legacy-note"
    write.payload = Data("legacy".utf8)
    write.createdAt = Date()
    write.attempts = 3
    write.status = WriteQueueStatus.failed.rawValue
    write.lastError = "Legacy retry failure"
    try context.save()
}
