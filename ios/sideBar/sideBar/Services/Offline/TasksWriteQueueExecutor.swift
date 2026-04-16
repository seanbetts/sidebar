import Foundation
import sideBarShared

final class TasksWriteQueueExecutor: WriteQueueExecutor {
    private let api: any TasksProviding
    private let store: any TasksWriteQueueApplying
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        api: any TasksProviding,
        store: any TasksWriteQueueApplying,
        refreshDebounceNanoseconds: UInt64 = 200_000_000
    ) {
        self.api = api
        self.store = store
        _ = refreshDebounceNanoseconds
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
        if response.applied.contains(operation.operationId),
           operation.op.lowercased() == "add",
           let placeholderId = store.pendingPlaceholderId(operationId: operation.operationId),
           let serverTaskId = syncedTaskID(for: operation, response: response) {
            await store.remapPendingTaskReferences(localID: placeholderId, serverID: serverTaskId)
        }
        store.applySyncResponse(response, operationId: operation.operationId)
        if let token = response.serverUpdatedSince {
            store.updateLastSyncToken(token)
        }
    }

    private func syncedTaskID(for operation: TaskOperationPayload, response: TaskSyncResponse) -> String? {
        let candidates = response.tasks + response.nextTasks + (response.updates?.tasks ?? [])
        guard !candidates.isEmpty else { return nil }

        if let title = operation.title,
           let matchingTitle = candidates.first(where: { $0.title == title }) {
            return matchingTitle.id
        }

        return candidates.first?.id
    }
}
