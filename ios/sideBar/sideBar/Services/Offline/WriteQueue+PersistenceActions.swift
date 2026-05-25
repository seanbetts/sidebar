import CoreData
import Foundation
import OSLog

@MainActor
extension WriteQueue {
    func fetchPendingWrites() async throws -> [PendingWriteSummary] {
        try await performBackgroundTask { context in
            let request = PendingWrite.fetchRequest()
            request.sortDescriptors = [
                NSSortDescriptor(keyPath: \PendingWrite.createdAt, ascending: false)
            ]
            let writes = try context.fetch(request)
            return writes.map(PendingWriteQueueMapper.summary)
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
            return PendingWriteQueueMapper.summary(from: write)
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

    func countQueuedWrites() async throws -> Int {
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
                let failedRows = failedWrites.map(PendingWriteQueueMapper.summary)

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
}
