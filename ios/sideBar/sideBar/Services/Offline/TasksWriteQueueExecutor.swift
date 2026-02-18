import Foundation
import sideBarShared

final class TasksWriteQueueExecutor: WriteQueueExecutor {
    private let api: any TasksProviding
    private let store: any TasksWriteQueueApplying
    private let refreshDebounceNanoseconds: UInt64
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var deferredRefreshTask: Task<Void, Never>?

    init(
        api: any TasksProviding,
        store: any TasksWriteQueueApplying,
        refreshDebounceNanoseconds: UInt64 = 200_000_000
    ) {
        self.api = api
        self.store = store
        self.refreshDebounceNanoseconds = refreshDebounceNanoseconds
    }

    func execute(write: PendingWriteRecord) async throws {
        guard write.entityType == WriteEntityType.task.rawValue else { return }
        deferredRefreshTask?.cancel()
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
        scheduleRefreshAfterSync()
    }

    private func scheduleRefreshAfterSync() {
        deferredRefreshTask = Task { [weak self] in
            guard let self else { return }
            if self.refreshDebounceNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: self.refreshDebounceNanoseconds)
            }
            guard !Task.isCancelled else { return }
            await self.store.refreshAfterSync()
        }
    }
}
