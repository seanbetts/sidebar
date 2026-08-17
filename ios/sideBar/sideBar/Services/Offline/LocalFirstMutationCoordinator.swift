import Foundation

@MainActor
struct LocalFirstMutationCoordinator {
    private weak var writeQueue: WriteQueue?

    init(writeQueue: WriteQueue?) {
        self.writeQueue = writeQueue
    }

    func enqueue<Payload: Encodable>(
        operation: WriteOperation,
        entityType: WriteEntityType,
        entityId: String?,
        payload: Payload,
        serverSnapshot: ServerSnapshot? = nil
    ) async throws {
        guard let writeQueue else {
            throw WriteQueueError.missingQueue
        }
        try await writeQueue.enqueue(
            operation: operation,
            entityType: entityType,
            entityId: entityId,
            payload: payload,
            serverSnapshot: serverSnapshot
        )
    }

    func enqueue<Payload: Encodable>(
        operation: WriteOperation,
        entityType: WriteEntityType,
        entityId: String?,
        payload: Payload,
        writeId: UUID,
        serverSnapshot: ServerSnapshot? = nil
    ) async throws {
        guard let writeQueue else {
            throw WriteQueueError.missingQueue
        }
        try await writeQueue.enqueue(
            operation: operation,
            entityType: entityType,
            entityId: entityId,
            payload: payload,
            serverSnapshot: serverSnapshot,
            writeId: writeId
        )
    }
}
