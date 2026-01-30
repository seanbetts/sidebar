import CoreData
import Foundation
import OSLog

@MainActor
/// Durable Core Data-backed storage for offline snapshots.
public final class OfflineStore {
    private let container: NSPersistentContainer
    private let logger = Logger(subsystem: "sideBar", category: "OfflineStore")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(container: NSPersistentContainer) {
        self.container = container
    }

    public func get<T: Decodable>(key: String, as type: T.Type) -> T? {
        guard let payload = fetchPayload(forKey: key) else {
            return nil
        }
        return decodePayload(payload, as: type)
    }

    public func getAll<T: Decodable>(keyPrefix: String, as type: T.Type) -> [T] {
        fetchPayloads(prefix: keyPrefix).compactMap { payload in
            decodePayload(payload, as: type)
        }
    }

    public func set<T: Encodable>(key: String, entityType: String, value: T, lastSyncAt: Date?) {
        do {
            let data = try encoder.encode(value)
            upsertEntry(key: key, entityType: entityType, payload: data, lastSyncAt: lastSyncAt)
        } catch {
            logger.error("OfflineStore set failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func lastSyncAt(for key: String) -> Date? {
        fetchLastSyncAt(forKey: key)
    }

    public func remove(key: String) {
        deleteEntry(forKey: key)
    }

    // MARK: - Core Data Helpers

    private func decodePayload<T: Decodable>(_ payload: Data, as type: T.Type) -> T? {
        do {
            return try decoder.decode(T.self, from: payload)
        } catch {
            logger.error("OfflineStore decode failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func fetchPayload(forKey key: String) -> Data? {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        var payload: Data?
        context.performAndWait {
            do {
                let request = OfflineEntry.fetchRequest()
                request.fetchLimit = 1
                request.predicate = NSPredicate(format: "key == %@", key)
                payload = try context.fetch(request).first?.payload
            } catch {
                logger.error("OfflineStore fetch failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return payload
    }

    private func fetchPayloads(prefix: String) -> [Data] {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        var payloads: [Data] = []
        context.performAndWait {
            do {
                let request = OfflineEntry.fetchRequest()
                request.predicate = NSPredicate(format: "key BEGINSWITH %@", prefix)
                let entries = try context.fetch(request)
                payloads = entries.map(\.payload)
            } catch {
                logger.error("OfflineStore fetchAll failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return payloads
    }

    private func fetchLastSyncAt(forKey key: String) -> Date? {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        var syncDate: Date?
        context.performAndWait {
            do {
                let request = OfflineEntry.fetchRequest()
                request.fetchLimit = 1
                request.predicate = NSPredicate(format: "key == %@", key)
                syncDate = try context.fetch(request).first?.lastSyncAt
            } catch {
                logger.error("OfflineStore lastSyncAt failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return syncDate
    }

    private func upsertEntry(key: String, entityType: String, payload: Data, lastSyncAt: Date?) {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.performAndWait {
            do {
                let request = OfflineEntry.fetchRequest()
                request.fetchLimit = 1
                request.predicate = NSPredicate(format: "key == %@", key)
                let entry = try context.fetch(request).first ?? OfflineEntry(context: context)
                if entry.objectID.isTemporaryID {
                    entry.id = UUID()
                }
                entry.key = key
                entry.entityType = entityType
                entry.payload = payload
                entry.updatedAt = Date()
                entry.lastSyncAt = lastSyncAt
                try context.save()
            } catch {
                logger.error("OfflineStore upsert failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func deleteEntry(forKey key: String) {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.performAndWait {
            do {
                let request = OfflineEntry.fetchRequest()
                request.predicate = NSPredicate(format: "key == %@", key)
                let entries = try context.fetch(request)
                entries.forEach { context.delete($0) }
                try context.save()
            } catch {
                logger.error("OfflineStore remove failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
