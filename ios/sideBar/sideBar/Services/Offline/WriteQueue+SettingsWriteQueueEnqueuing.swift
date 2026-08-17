import Foundation

extension WriteQueue: SettingsWriteQueueEnqueuing {
    func enqueue<T: Encodable>(
        operation: WriteOperation,
        entityType: WriteEntityType,
        entityId: String?,
        payload: T,
        serverSnapshot: ServerSnapshot?
    ) async throws {
        try await enqueue(
            operation: operation,
            entityType: entityType,
            entityId: entityId,
            payload: payload,
            serverSnapshot: serverSnapshot,
            writeId: UUID()
        )
    }
}
