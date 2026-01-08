import CoreData
import Foundation

public extension CacheEntry {
    @nonobjc
    class func fetchRequest() -> NSFetchRequest<CacheEntry> {
        NSFetchRequest<CacheEntry>(entityName: "CacheEntry")
    }

    @NSManaged var key: String
    @NSManaged var payload: Data
    @NSManaged var expiresAt: Date
    @NSManaged var createdAt: Date?
    @NSManaged var updatedAt: Date?
    @NSManaged var typeName: String?
}
