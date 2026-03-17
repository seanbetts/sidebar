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

    func restoreConflictPauseState() async {
        do {
            let hasConflict = try await hasOutstandingConflictWrites()
            setConflictPauseState(hasConflict)
        } catch {
            logger.error("Failed to restore conflict pause state: \(error.localizedDescription, privacy: .public)")
        }
    }

    func hasOutstandingConflictWrites() async throws -> Bool {
        try await runRecoveryBackgroundTask(container: container) { context in
            let request = PendingWrite.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "conflictReason != nil")
            return try context.count(for: request) > 0
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
