import Foundation

extension TasksStore {
    func enqueueOperation(_ operation: TaskOperationPayload) async throws {
        guard let writeQueue else { throw WriteQueueError.missingQueue }
        try await writeQueue.enqueue(
            operation: .update,
            entityType: .task,
            entityId: operation.id,
            payload: operation
        )
    }

    func enqueueBatch(_ batch: TaskOperationBatch) async throws {
        for operation in batch.operations {
            try await enqueueOperation(operation)
        }
    }

    func refreshAfterSync() async {
        guard selection != .none else {
            return
        }
        await load(selection: selection, force: true)
        await loadCounts(force: true)
    }
}

enum LocalTaskOperation {
    case add
    case remove
    case rename
    case notes
    case move
    case setDue
    case clearDue
    case setRepeat
}

extension TaskSelection {
    var isSearch: Bool { if case .search = self { true } else { false } }
}
