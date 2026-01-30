import Foundation

final class CompositeWriteQueueExecutor: WriteQueueExecutor {
    private let executors: [WriteEntityType: WriteQueueExecutor]

    init(executors: [WriteEntityType: WriteQueueExecutor]) {
        self.executors = executors
    }

    func execute(write: PendingWriteRecord) async throws {
        guard let entityType = WriteEntityType(rawValue: write.entityType) else {
            return
        }
        guard let executor = executors[entityType] else {
            throw WriteQueueError.missingExecutor
        }
        try await executor.execute(write: write)
    }
}
