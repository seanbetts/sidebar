import Foundation

final class FilesWriteQueueExecutor: WriteQueueExecutor {
    private let api: any IngestionProviding
    private let store: any FilesWriteQueueApplying
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(api: any IngestionProviding, store: any FilesWriteQueueApplying) {
        self.api = api
        self.store = store
    }

    func execute(write: PendingWriteRecord) async throws {
        guard write.entityType == WriteEntityType.file.rawValue else { return }
        if write.operationType == WriteOperation.reorder.rawValue {
            let payload = try decoder.decode(PinnedOrderPayload.self, from: write.payload)
            try await api.updatePinnedOrder(ids: payload.ids)
            return
        }
        let operation = try decoder.decode(IngestionOperationPayload.self, from: write.payload)
        let request = IngestionSyncRequest(lastSync: nil, operations: [operation])
        let response = try await api.sync(request)
        if let conflict = response.conflicts.first(where: { $0.operationId == operation.operationId }) {
            let encoded = try? encoder.encode(conflict)
            throw WriteQueueConflictError(
                reason: conflict.reason ?? "File changed on another device.",
                serverSnapshot: encoded
            )
        }
        response.files.forEach { store.applySyncFile($0) }
        response.updates?.items.forEach { store.applySyncFile($0) }
    }
}
