import CoreData
import Foundation

struct DraftInfo: Equatable {
    let content: String
    let savedAt: Date
    let syncedAt: Date?
}

@MainActor
final class DraftStorage {
    private let container: NSPersistentContainer

    init(container: NSPersistentContainer) {
        self.container = container
    }

    func saveDraft(entityType: String, entityId: String, content: String) throws {
        let context = container.viewContext
        let request = LocalDraft.fetchRequest()
        request.predicate = NSPredicate(format: "entityType == %@ AND entityId == %@", entityType, entityId)
        let draft = (try context.fetch(request).first) ?? LocalDraft(context: context)
        if draft.objectID.isTemporaryID {
            draft.id = UUID()
        }
        draft.entityType = entityType
        draft.entityId = entityId
        draft.content = content
        draft.savedAt = Date()
        try context.save()
    }

    func getDraft(entityType: String, entityId: String) throws -> DraftInfo? {
        let context = container.viewContext
        let request = LocalDraft.fetchRequest()
        request.predicate = NSPredicate(format: "entityType == %@ AND entityId == %@", entityType, entityId)
        guard let draft = try context.fetch(request).first else { return nil }
        return DraftInfo(content: draft.content, savedAt: draft.savedAt, syncedAt: draft.syncedAt)
    }

    func markSynced(entityType: String, entityId: String) throws {
        let context = container.viewContext
        let request = LocalDraft.fetchRequest()
        request.predicate = NSPredicate(format: "entityType == %@ AND entityId == %@", entityType, entityId)
        guard let draft = try context.fetch(request).first else { return }
        draft.syncedAt = Date()
        try context.save()
    }

    func deleteDraft(entityType: String, entityId: String) throws {
        let context = container.viewContext
        let request = LocalDraft.fetchRequest()
        request.predicate = NSPredicate(format: "entityType == %@ AND entityId == %@", entityType, entityId)
        if let draft = try context.fetch(request).first {
            context.delete(draft)
            try context.save()
        }
    }
}
