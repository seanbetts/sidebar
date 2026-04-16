import CoreData
import Foundation

extension WriteQueue {
    func applyServerIdentityMap(
        entityType: WriteEntityType,
        localID: String,
        serverID: String
    ) async throws {
        guard localID != serverID else { return }

        try await performBackgroundTask { context in
            let request = PendingWrite.fetchRequest()
            request.predicate = NSPredicate(format: "entityType == %@", entityType.rawValue)
            let writes = try context.fetch(request)

            for write in writes {
                if write.entityId == localID {
                    write.entityId = serverID
                }

                if let remappedPayload = remapQueuedPayloadIdentity(
                    entityType: entityType,
                    payloadData: write.payload,
                    localID: localID,
                    serverID: serverID
                ) {
                    write.payload = remappedPayload
                }
            }
        }

        await loadQueueCounts()
    }
}

private func remapQueuedPayloadIdentity(
    entityType: WriteEntityType,
    payloadData: Data,
    localID: String,
    serverID: String
) -> Data? {
    switch entityType {
    case .task:
        return remapTaskPayloadIdentity(payloadData: payloadData, localID: localID, serverID: serverID)
    case .website:
        return remapWebsitePayloadIdentity(payloadData: payloadData, localID: localID, serverID: serverID)
    case .file:
        return remapIngestionPayloadIdentity(payloadData: payloadData, localID: localID, serverID: serverID)
    default:
        return nil
    }
}

private func remapTaskPayloadIdentity(payloadData: Data, localID: String, serverID: String) -> Data? {
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()
    guard let payload = try? decoder.decode(TaskOperationPayload.self, from: payloadData),
          payload.id == localID else {
        return nil
    }

    let remapped = TaskOperationPayload(
        operationId: payload.operationId,
        op: payload.op,
        id: serverID,
        title: payload.title,
        notes: payload.notes,
        listId: payload.listId,
        dueDate: payload.dueDate,
        startDate: payload.startDate,
        recurrenceRule: payload.recurrenceRule,
        clientUpdatedAt: payload.clientUpdatedAt
    )
    return try? encoder.encode(remapped)
}

private func remapWebsitePayloadIdentity(payloadData: Data, localID: String, serverID: String) -> Data? {
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()
    guard let payload = try? decoder.decode(WebsiteOperationPayload.self, from: payloadData),
          payload.id == localID else {
        return nil
    }

    let remapped = WebsiteOperationPayload(
        operationId: payload.operationId,
        op: payload.op,
        id: serverID,
        title: payload.title,
        pinned: payload.pinned,
        archived: payload.archived,
        clientUpdatedAt: payload.clientUpdatedAt
    )
    return try? encoder.encode(remapped)
}

private func remapIngestionPayloadIdentity(payloadData: Data, localID: String, serverID: String) -> Data? {
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()
    guard let payload = try? decoder.decode(IngestionOperationPayload.self, from: payloadData),
          payload.id == localID else {
        return nil
    }

    let remapped = IngestionOperationPayload(
        operationId: payload.operationId,
        op: payload.op,
        id: serverID,
        filename: payload.filename,
        pinned: payload.pinned,
        clientUpdatedAt: payload.clientUpdatedAt
    )
    return try? encoder.encode(remapped)
}
