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
           let placeholderId = store.pendingPlaceholderId(operationId: operation.operationId),
           let serverEntityId = syncedEntityID(for: operation, response: response) {
            await store.remapPendingTaskReferences(localID: placeholderId, serverID: serverEntityId)
        }
        store.applySyncResponse(response, operationId: operation.operationId)
        if let token = response.serverUpdatedSince {
            store.updateLastSyncToken(token)
        }
    }

    private func syncedEntityID(for operation: TaskOperationPayload, response: TaskSyncResponse) -> String? {
        switch operation.op.lowercased() {
        case "add":
            let candidates = response.tasks + response.nextTasks + (response.updates?.tasks ?? [])
            if let title = operation.title,
               let matchingTitle = candidates.first(where: { $0.title == title }) {
                return matchingTitle.id
            }
            return candidates.first?.id
        case "create_group":
            let candidates = response.updates?.groups ?? []
            if let title = operation.title,
               let matchingTitle = candidates.first(where: { $0.title == title && $0.deletedAt == nil }) {
                return matchingTitle.id
            }
            return candidates.first(where: { $0.deletedAt == nil })?.id
        case "create_project":
            let candidates = response.updates?.projects ?? []
            if let title = operation.title,
               let matchingTitle = candidates.first(where: { $0.title == title && $0.deletedAt == nil }) {
                return matchingTitle.id
            }
            return candidates.first(where: { $0.deletedAt == nil })?.id
        default:
            return nil
        }
    }
}
