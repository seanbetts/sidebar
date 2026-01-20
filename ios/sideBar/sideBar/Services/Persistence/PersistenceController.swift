import CoreData
import Foundation

public final class PersistenceController {
    public static let shared = PersistenceController()

    public let container: NSPersistentContainer

    public init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "SideBarCache")

        container.persistentStoreDescriptions.forEach { description in
            description.setOption(
                FileProtectionType.complete as NSObject,
                forKey: NSPersistentStoreFileProtectionKey
            )
        }

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { _description, error in
            if let error {
                assertionFailure("Failed to load persistent stores: \(error)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}
