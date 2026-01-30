import CoreData
import Foundation

public extension PendingWrite {
    @nonobjc
    class func fetchRequest() -> NSFetchRequest<PendingWrite> {
        NSFetchRequest<PendingWrite>(entityName: "PendingWrite")
    }

    @NSManaged var id: UUID
    @NSManaged var operationType: String
    @NSManaged var entityType: String
    @NSManaged var entityId: String?
    @NSManaged var payload: Data
    @NSManaged var createdAt: Date
    @NSManaged var attempts: Int16
    @NSManaged var conflictReason: String?
    @NSManaged var lastAttemptAt: Date?
    @NSManaged var lastError: String?
    @NSManaged var status: String
    @NSManaged var serverSnapshot: Data?
}
