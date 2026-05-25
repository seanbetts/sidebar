import CoreData
import Foundation
import OSLog

@MainActor
extension WriteQueue {
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

    func autoResolveConflict(write: PendingWriteRecord, error: WriteQueueConflictError) async {
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
