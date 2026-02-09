import CoreData
import Foundation

@objc(OfflineEntry)
public final class OfflineEntry: NSManagedObject {
    static func insertNew(in context: NSManagedObjectContext) -> OfflineEntry {
        guard let entity = NSEntityDescription.entity(forEntityName: "OfflineEntry", in: context) else {
            preconditionFailure("Missing OfflineEntry entity description")
        }
        return OfflineEntry(entity: entity, insertInto: context)
    }
}
