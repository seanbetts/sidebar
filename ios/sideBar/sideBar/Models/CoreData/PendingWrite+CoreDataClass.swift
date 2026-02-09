import CoreData
import Foundation

@objc(PendingWrite)
public final class PendingWrite: NSManagedObject {
    static func insertNew(in context: NSManagedObjectContext) -> PendingWrite {
        guard let entity = NSEntityDescription.entity(forEntityName: "PendingWrite", in: context) else {
            preconditionFailure("Missing PendingWrite entity description")
        }
        return PendingWrite(entity: entity, insertInto: context)
    }
}
