import CoreData
import Foundation

public extension LocalDraft {
    @nonobjc
    class func fetchRequest() -> NSFetchRequest<LocalDraft> {
        NSFetchRequest<LocalDraft>(entityName: "LocalDraft")
    }

    @NSManaged var id: UUID
    @NSManaged var entityType: String
    @NSManaged var entityId: String
    @NSManaged var content: String
    @NSManaged var savedAt: Date
    @NSManaged var syncedAt: Date?
}
