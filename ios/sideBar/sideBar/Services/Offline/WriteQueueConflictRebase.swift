import Foundation

func rebaseConflictPayload(
    entityType: String,
    payloadData: Data,
    serverSnapshot: Data?
) -> Data? {
    switch entityType {
    case WriteEntityType.task.rawValue:
        return rebaseTaskPayload(payloadData: payloadData, serverSnapshot: serverSnapshot)
    case WriteEntityType.file.rawValue:
        return rebaseIngestionPayload(payloadData: payloadData, serverSnapshot: serverSnapshot)
    case WriteEntityType.website.rawValue:
        return rebaseWebsitePayload(payloadData: payloadData, serverSnapshot: serverSnapshot)
    default:
        return nil
    }
}

private func rebaseTaskPayload(payloadData: Data, serverSnapshot: Data?) -> Data? {
    guard let serverSnapshot else { return nil }
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()
    guard let conflict = try? decoder.decode(TaskSyncConflict.self, from: serverSnapshot),
          let serverUpdatedAt = conflict.serverUpdatedAt,
          let payload = try? decoder.decode(TaskOperationPayload.self, from: payloadData) else {
        return nil
    }
    let rebased = TaskOperationPayload(
        operationId: payload.operationId,
        op: payload.op,
        id: payload.id,
        title: payload.title,
        notes: payload.notes,
        listId: payload.listId,
        dueDate: payload.dueDate,
        startDate: payload.startDate,
        recurrenceRule: payload.recurrenceRule,
        clientUpdatedAt: serverUpdatedAt
    )
    return try? encoder.encode(rebased)
}

private func rebaseIngestionPayload(payloadData: Data, serverSnapshot: Data?) -> Data? {
    guard let serverSnapshot else { return nil }
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()
    guard let conflict = try? decoder.decode(IngestionSyncConflict.self, from: serverSnapshot),
          let serverUpdatedAt = conflict.serverUpdatedAt,
          let payload = try? decoder.decode(IngestionOperationPayload.self, from: payloadData) else {
        return nil
    }
    let rebased = IngestionOperationPayload(
        operationId: payload.operationId,
        op: payload.op,
        id: payload.id,
        filename: payload.filename,
        pinned: payload.pinned,
        clientUpdatedAt: serverUpdatedAt
    )
    return try? encoder.encode(rebased)
}

private func rebaseWebsitePayload(payloadData: Data, serverSnapshot: Data?) -> Data? {
    guard let serverSnapshot else { return nil }
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()
    guard let conflict = try? decoder.decode(WebsiteSyncConflict.self, from: serverSnapshot),
          let serverUpdatedAt = conflict.serverUpdatedAt,
          let payload = try? decoder.decode(WebsiteOperationPayload.self, from: payloadData) else {
        return nil
    }
    let rebased = WebsiteOperationPayload(
        operationId: payload.operationId,
        op: payload.op,
        id: payload.id,
        title: payload.title,
        pinned: payload.pinned,
        archived: payload.archived,
        clientUpdatedAt: serverUpdatedAt
    )
    return try? encoder.encode(rebased)
}
