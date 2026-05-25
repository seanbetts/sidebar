import CoreData
import Foundation

@MainActor
extension WriteQueue {
    func coalesceNoteUpdate(entityId: String, payload: Data) async throws -> Bool {
        try await performBackgroundTask { context in
            let request = PendingWrite.fetchRequest()
            request.predicate = NSPredicate(
                format: "operationType == %@ AND entityType == %@ AND entityId == %@ AND (status == %@ OR status == %@)",
                WriteOperation.update.rawValue,
                WriteEntityType.note.rawValue,
                entityId,
                WriteQueueStatus.pending.rawValue,
                WriteQueueStatus.failed.rawValue
            )
            request.sortDescriptors = [NSSortDescriptor(keyPath: \PendingWrite.createdAt, ascending: false)]
            request.fetchLimit = 1
            guard let write = try context.fetch(request).first else {
                return false
            }
            write.payload = payload
            write.createdAt = Date()
            write.status = WriteQueueStatus.pending.rawValue
            write.attempts = 0
            write.lastError = nil
            write.lastAttemptAt = nil
            return true
        }
    }

    func coalesceTaskNotesUpdate(entityId: String, payload: Data) async throws -> Bool {
        guard WriteQueueCoalescingPolicy.isTaskNotesUpdate(payload) else { return false }
        return try await performBackgroundTask { context in
            let request = PendingWrite.fetchRequest()
            request.predicate = NSPredicate(
                format: "operationType == %@ AND entityType == %@ AND entityId == %@ AND (status == %@ OR status == %@)",
                WriteOperation.update.rawValue,
                WriteEntityType.task.rawValue,
                entityId,
                WriteQueueStatus.pending.rawValue,
                WriteQueueStatus.failed.rawValue
            )
            request.sortDescriptors = [NSSortDescriptor(keyPath: \PendingWrite.createdAt, ascending: false)]
            request.fetchLimit = 1
            guard let write = try context.fetch(request).first,
                  WriteQueueCoalescingPolicy.isTaskNotesUpdate(write.payload) else { return false }
            write.payload = payload
            write.createdAt = Date()
            write.status = WriteQueueStatus.pending.rawValue
            write.attempts = 0
            write.lastError = nil
            write.lastAttemptAt = nil
            return true
        }
    }

    func coalesceSettingsUpdate(payload: Data) async throws -> Bool {
        let incoming = try? JSONDecoder().decode(SettingsMutationPayload.self, from: payload)
        guard let incoming, incoming.kind == .settingsPatch else { return false }
        return try await performBackgroundTask { context in
            let request = PendingWrite.fetchRequest()
            request.predicate = NSPredicate(
                format: "operationType == %@ AND entityType == %@ AND entityId == %@ AND (status == %@ OR status == %@)",
                WriteOperation.update.rawValue,
                WriteEntityType.settings.rawValue,
                incoming.entityId,
                WriteQueueStatus.pending.rawValue,
                WriteQueueStatus.failed.rawValue
            )
            request.sortDescriptors = [NSSortDescriptor(keyPath: \PendingWrite.createdAt, ascending: false)]
            request.fetchLimit = 1
            guard let write = try context.fetch(request).first,
                  let merged = WriteQueueCoalescingPolicy.mergedSettingsPatch(
                    existing: write.payload,
                    incoming: payload
                  ) else { return false }
            write.payload = merged
            write.createdAt = Date()
            write.status = WriteQueueStatus.pending.rawValue
            write.attempts = 0
            write.lastError = nil
            write.lastAttemptAt = nil
            write.conflictReason = nil
            write.serverSnapshot = nil
            return true
        }
    }
}
