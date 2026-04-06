import CoreData
import Foundation
import OSLog

extension WriteQueue {
    func recoverStuckWritesIfNeeded() async {
        guard !hasRecoveredStuckWrites else { return }
        hasRecoveredStuckWrites = true
        do {
            let recoveredCount = try await runRecoveryBackgroundTask(container: container) { context in
                let request = PendingWrite.fetchRequest()
                request.predicate = NSPredicate(
                    format: "status == %@",
                    WriteQueueStatus.inProgress.rawValue
                )
                let writes = try context.fetch(request)
                for write in writes {
                    write.status = WriteQueueStatus.pending.rawValue
                }
                return writes.count
            }
            if recoveredCount > 0 {
                logger.info("Recovered \(recoveredCount, privacy: .public) stuck write(s)")
            }
        } catch {
            logger.error("Failed to recover stuck writes: \(error.localizedDescription, privacy: .public)")
        }
    }

    func recoverConflictWritesIfNeeded() async {
        guard !hasRecoveredConflictWrites else { return }
        hasRecoveredConflictWrites = true
        do {
            let recoveredCount = try await runRecoveryBackgroundTask(container: container) { context in
                let request = PendingWrite.fetchRequest()
                request.predicate = NSPredicate(format: "conflictReason != nil")
                let writes = try context.fetch(request)
                for write in writes {
                    let rebasedPayload = rebaseConflictPayload(
                        entityType: write.entityType,
                        payloadData: write.payload,
                        serverSnapshot: write.serverSnapshot
                    )
                    if let rebasedPayload {
                        write.payload = rebasedPayload
                        write.status = WriteQueueStatus.pending.rawValue
                        write.attempts = 0
                        write.lastError = nil
                        write.lastAttemptAt = nil
                    } else {
                        write.status = WriteQueueStatus.failed.rawValue
                        write.lastError = write.lastError ?? "Automatic conflict resolution failed."
                    }
                    write.conflictReason = nil
                    write.serverSnapshot = nil
                }
                return writes.count
            }
            if recoveredCount > 0 {
                logger.info("Recovered \(recoveredCount, privacy: .public) conflict write(s)")
            }
        } catch {
            logger.error("Failed to recover conflict writes: \(error.localizedDescription, privacy: .public)")
        }
    }
}

private func runRecoveryBackgroundTask<T>(
    container: NSPersistentContainer,
    work: @escaping (NSManagedObjectContext) throws -> T
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
