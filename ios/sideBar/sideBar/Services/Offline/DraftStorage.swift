import CoreData
import Foundation

struct DraftInfo: Equatable {
    let content: String
    let canonicalContent: String
    let savedAt: Date
    let syncedAt: Date?
}

@MainActor
final class DraftStorage {
    private let container: NSPersistentContainer

    init(container: NSPersistentContainer) {
        self.container = container
    }

    func saveDraft(
        entityType: String,
        entityId: String,
        content: String,
        canonicalContent: String? = nil
    ) throws {
        let context = container.viewContext
        let request = LocalDraft.fetchRequest()
        request.predicate = NSPredicate(format: "entityType == %@ AND entityId == %@", entityType, entityId)
        let draft = (try context.fetch(request).first) ?? LocalDraft.insertNew(in: context)
        if draft.objectID.isTemporaryID {
            draft.id = UUID()
        }
        draft.entityType = entityType
        draft.entityId = entityId
        draft.content = canonicalContent ?? content
        draft.savedAt = Date()
        draft.syncedAt = nil
        try context.save()
    }

    func getDraft(entityType: String, entityId: String) throws -> DraftInfo? {
        let context = container.viewContext
        let request = LocalDraft.fetchRequest()
        request.predicate = NSPredicate(format: "entityType == %@ AND entityId == %@", entityType, entityId)
        guard let draft = try context.fetch(request).first else { return nil }
        let storedContent = draft.content
        if let document = NotesSemanticDocumentCodec.decode(storedContent) {
            return DraftInfo(
                content: NotesSemanticDocumentProjection.plainText(from: document),
                canonicalContent: storedContent,
                savedAt: draft.savedAt,
                syncedAt: draft.syncedAt
            )
        }
        let canonicalContent =
            NotesSemanticDocumentCodec.encode(
                NotesSemanticDocumentProjection.document(fromPlainText: storedContent)
            ) ?? ""
        return DraftInfo(
            content: storedContent,
            canonicalContent: canonicalContent,
            savedAt: draft.savedAt,
            syncedAt: draft.syncedAt
        )
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

    func cleanupSyncedDrafts(olderThan days: Int) throws {
        guard days > 0 else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let context = container.newBackgroundContext()
        var capturedError: Error?
        context.performAndWait {
            do {
                let request = LocalDraft.fetchRequest()
                request.predicate = NSPredicate(format: "syncedAt != nil AND syncedAt < %@", cutoff as NSDate)
                let drafts = try context.fetch(request)
                drafts.forEach { context.delete($0) }
                if context.hasChanges {
                    try context.save()
                }
            } catch {
                capturedError = error
            }
        }
        if let capturedError {
            throw capturedError
        }
    }

    func clearAllDrafts() throws {
        let context = container.newBackgroundContext()
        let shouldBatchDelete = supportsBatchDelete
        let viewContext = container.viewContext
        var capturedError: Error?
        context.performAndWait {
            do {
                if shouldBatchDelete {
                    try Self.batchDeleteAllDrafts(in: context, viewContext: viewContext)
                } else {
                    try Self.fetchAndDeleteAllDrafts(in: context, viewContext: viewContext)
                }
            } catch {
                capturedError = error
            }
        }
        if let capturedError {
            throw capturedError
        }
    }

    private var supportsBatchDelete: Bool {
        let stores = container.persistentStoreCoordinator.persistentStores
        return !stores.isEmpty && stores.allSatisfy { $0.type == NSSQLiteStoreType }
    }

    nonisolated private static func batchDeleteAllDrafts(
        in context: NSManagedObjectContext,
        viewContext: NSManagedObjectContext
    ) throws {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "LocalDraft")
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        deleteRequest.resultType = .resultTypeObjectIDs
        let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
        if let deletedObjectIDs = result?.result as? [NSManagedObjectID] {
            mergeDeletedDrafts(deletedObjectIDs, into: viewContext)
        }
    }

    nonisolated private static func fetchAndDeleteAllDrafts(
        in context: NSManagedObjectContext,
        viewContext: NSManagedObjectContext
    ) throws {
        let request = NSFetchRequest<LocalDraft>(entityName: "LocalDraft")
        request.includesPropertyValues = false
        let drafts = try context.fetch(request)
        let deletedObjectIDs = drafts.map(\.objectID)
        drafts.forEach { context.delete($0) }
        if context.hasChanges {
            try context.save()
        }
        mergeDeletedDrafts(deletedObjectIDs, into: viewContext)
    }

    nonisolated private static func mergeDeletedDrafts(
        _ deletedObjectIDs: [NSManagedObjectID],
        into viewContext: NSManagedObjectContext
    ) {
        guard !deletedObjectIDs.isEmpty else { return }
        let changes: [AnyHashable: Any] = [NSDeletedObjectsKey: deletedObjectIDs]
        NSManagedObjectContext.mergeChanges(
            fromRemoteContextSave: changes,
            into: [viewContext]
        )
    }
}
