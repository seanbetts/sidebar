import CoreData
import Foundation

struct DraftInfo: Equatable {
    let content: String
    let savedAt: Date
    let syncedAt: Date?
}

actor DraftStorage {
    private let container: NSPersistentContainer

    init(container: NSPersistentContainer) {
        self.container = container
    }

    func saveDraft(entityType: String, entityId: String, content: String) async throws {
        try await perform { context in
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
        }
    }

    func getDraft(entityType: String, entityId: String) async throws -> DraftInfo? {
        try await perform { context in
            let request = LocalDraft.fetchRequest()
            request.predicate = NSPredicate(format: "entityType == %@ AND entityId == %@", entityType, entityId)
            guard let draft = try context.fetch(request).first else { return nil }
            return DraftInfo(content: draft.content, savedAt: draft.savedAt, syncedAt: draft.syncedAt)
        }
    }

    func markSynced(entityType: String, entityId: String) async throws {
        try await perform { context in
            let request = LocalDraft.fetchRequest()
            request.predicate = NSPredicate(format: "entityType == %@ AND entityId == %@", entityType, entityId)
            guard let draft = try context.fetch(request).first else { return }
            draft.syncedAt = Date()
        }
    }

    func deleteDraft(entityType: String, entityId: String) async throws {
        try await perform { context in
            let request = LocalDraft.fetchRequest()
            request.predicate = NSPredicate(format: "entityType == %@ AND entityId == %@", entityType, entityId)
            if let draft = try context.fetch(request).first {
                context.delete(draft)
            }
        }
    }

    private func perform<T>(_ block: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let context = container.newBackgroundContext()
            context.perform {
                do {
                    let result = try block(context)
                    if context.hasChanges {
                        try context.save()
                    }
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
