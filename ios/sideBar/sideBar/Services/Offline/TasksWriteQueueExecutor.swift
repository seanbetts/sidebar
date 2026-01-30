import Foundation
import sideBarShared

final class TasksWriteQueueExecutor: WriteQueueExecutor {
    private let api: any TasksProviding
    private let store: TasksStore
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(api: any TasksProviding, store: TasksStore) {
        self.api = api
        self.store = store
    }

    func execute(write: PendingWriteRecord) async throws {
        guard write.entityType == WriteEntityType.task.rawValue else { return }
        let operation = try decoder.decode(TaskOperationPayload.self, from: write.payload)
        let request = TaskSyncRequest(lastSync: store.lastSyncToken(), operations: [operation])
        let response = try await api.sync(request)
        if let conflict = response.conflicts.first(where: { $0.operationId == operation.operationId }) {
            let encoded = try? encoder.encode(conflict)
            throw WriteQueueConflictError(
                reason: "Task changed on another device.",
                serverSnapshot: encoded
            )
        }
        if response.applied.contains(operation.operationId) {
            store.removePendingTaskPlaceholder(operationId: operation.operationId)
        }
        if let token = response.serverUpdatedSince {
            store.updateLastSyncToken(token)
        }
        await store.refreshAfterSync()
    }
}
