import Foundation

final class WebsitesWriteQueueExecutor: WriteQueueExecutor {
    private let api: any WebsitesProviding
    private let store: any WebsitesWriteQueueApplying
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(api: any WebsitesProviding, store: any WebsitesWriteQueueApplying) {
        self.api = api
        self.store = store
    }

    func execute(write: PendingWriteRecord) async throws {
        guard write.entityType == WriteEntityType.website.rawValue else { return }
        if write.operationType == WriteOperation.reorder.rawValue {
            let payload = try decoder.decode(PinnedOrderPayload.self, from: write.payload)
            try await api.updatePinnedOrder(ids: payload.ids)
            return
        }
        let operation = try decoder.decode(WebsiteOperationPayload.self, from: write.payload)
        let request = WebsiteSyncRequest(lastSync: nil, operations: [operation])
        let response = try await api.sync(request)
        if let conflict = response.conflicts.first(where: { $0.operationId == operation.operationId }) {
            let encoded = try? encoder.encode(conflict)
            throw WriteQueueConflictError(
                reason: conflict.reason ?? "Website changed on another device.",
                serverSnapshot: encoded
            )
        }
        let syncedItems = response.websites + (response.updates?.items ?? [])
        store.applySyncItems(syncedItems)
    }
}
