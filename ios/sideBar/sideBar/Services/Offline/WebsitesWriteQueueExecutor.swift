import Foundation

final class WebsitesWriteQueueExecutor: WriteQueueExecutor {
    private let api: any WebsitesProviding
    private let store: WebsitesStore
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(api: any WebsitesProviding, store: WebsitesStore) {
        self.api = api
        self.store = store
    }

    func execute(write: PendingWriteRecord) async throws {
        guard write.entityType == WriteEntityType.website.rawValue else { return }
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
        response.websites.forEach { store.applySyncItem($0) }
        response.updates?.items.forEach { store.applySyncItem($0) }
    }
}
