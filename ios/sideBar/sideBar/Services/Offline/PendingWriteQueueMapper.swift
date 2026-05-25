import Foundation

enum PendingWriteQueueMapper {
    static func summary(from write: PendingWrite) -> PendingWriteSummary {
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

    static func record(from write: PendingWrite) -> PendingWriteRecord {
        PendingWriteRecord(
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
