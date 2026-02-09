import CoreData
import Foundation

@objc(LocalDraft)
public final class LocalDraft: NSManagedObject {
    static func insertNew(in context: NSManagedObjectContext) -> LocalDraft {
        guard let entity = NSEntityDescription.entity(forEntityName: "LocalDraft", in: context) else {
            preconditionFailure("Missing LocalDraft entity description")
        }
        return LocalDraft(entity: entity, insertInto: context)
    }
}
