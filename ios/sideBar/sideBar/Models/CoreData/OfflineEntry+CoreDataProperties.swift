import CoreData
import Foundation

public extension OfflineEntry {
    @nonobjc
    class func fetchRequest() -> NSFetchRequest<OfflineEntry> {
        NSFetchRequest<OfflineEntry>(entityName: "OfflineEntry")
    }

    @NSManaged var id: UUID
    @NSManaged var key: String
    @NSManaged var payload: Data
    @NSManaged var entityType: String
    @NSManaged var updatedAt: Date
    @NSManaged var lastSyncAt: Date?
}
