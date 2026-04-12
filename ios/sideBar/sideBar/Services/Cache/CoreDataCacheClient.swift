import CoreData
import sideBarShared
import Foundation
import OSLog

/// Core Data-backed cache implementation.
public final class CoreDataCacheClient: CacheClient {
    private let container: NSPersistentContainer
    private let backgroundContext: NSManagedObjectContext
    private let logger = Logger(subsystem: "sideBar", category: "Cache")

    public init(container: NSPersistentContainer) {
        self.container = container
        let backgroundContext = container.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        self.backgroundContext = backgroundContext
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    public func get<T: Codable>(key: String) -> T? {
        var decoded: T?
        let context = backgroundContext
        context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "CacheEntry")
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "key == %@", key)

            do {
                guard let entry = try context.fetch(request).first else {
                    return
                }

                guard let expiresAt = entry.value(forKey: "expiresAt") as? Date else {
                    context.delete(entry)
                    do {
                        try context.save()
                    } catch {
                        self.logger.error("Cache entry cleanup failed: \(error.localizedDescription, privacy: .public)")
                    }
                    return
                }

                let payload = entry.value(forKey: "payload") as? Data
                if Date() > expiresAt {
                    context.delete(entry)
                    do {
                        try context.save()
                    } catch {
                        self.logger.error("Cache entry cleanup failed: \(error.localizedDescription, privacy: .public)")
                    }
                    return
                }

                guard let payload else {
                    self.logger.error("Cache decode failed: missing payload")
                    return
                }

                do {
                    decoded = try JSONDecoder().decode(T.self, from: payload)
                } catch {
                    self.logger.error("Cache decode failed: \(error.localizedDescription, privacy: .public)")
                }
            } catch {
                self.logger.error("Cache fetch failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return decoded
    }

    public func setEncoded(key: String, payload data: Data, typeName: String, ttlSeconds: TimeInterval) {
        let now = Date()
        let expiresAt = now.addingTimeInterval(ttlSeconds)

        backgroundContext.performAndWait {
            let context = backgroundContext
            let request = NSFetchRequest<NSManagedObject>(entityName: "CacheEntry")
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "key == %@", key)

            let entry: NSManagedObject
            do {
                entry = try context.fetch(request).first ?? self.makeEntry(in: context)
            } catch {
                self.logger.error("Cache fetch failed: \(error.localizedDescription, privacy: .public)")
                entry = self.makeEntry(in: context)
            }
            entry.setValue(key, forKey: "key")
            entry.setValue(data, forKey: "payload")
            entry.setValue(expiresAt, forKey: "expiresAt")
            entry.setValue(now, forKey: "updatedAt")
            entry.setValue(typeName, forKey: "typeName")
            if entry.value(forKey: "createdAt") == nil {
                entry.setValue(now, forKey: "createdAt")
            }

            do {
                try context.save()
            } catch {
                self.logger.error("Cache save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func remove(key: String) {
        let context = backgroundContext
        context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "CacheEntry")
            request.predicate = NSPredicate(format: "key == %@", key)
            do {
                let items = try context.fetch(request)
                for item in items {
                    context.delete(item)
                }
                try context.save()
            } catch {
                self.logger.error("Cache remove failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func clear() {
        let context = backgroundContext
        context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "CacheEntry")
            do {
                let items = try context.fetch(request)
                for item in items {
                    context.delete(item)
                }
                try context.save()
            } catch {
                self.logger.error("Cache clear failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func makeEntry(in context: NSManagedObjectContext) -> NSManagedObject {
        NSEntityDescription.insertNewObject(forEntityName: "CacheEntry", into: context)
    }
}
