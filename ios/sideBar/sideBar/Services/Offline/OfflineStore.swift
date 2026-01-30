import CoreData
import Foundation
import OSLog

/// Limits for retained offline snapshots by entity type.
public struct OfflineSnapshotRetention: Sendable {
    public let maxNotes: Int
    public let maxWebsites: Int
    public let maxFiles: Int
    public let maxConversations: Int

    public init(
        maxNotes: Int = 200,
        maxWebsites: Int = 500,
        maxFiles: Int = 500,
        maxConversations: Int = 100
    ) {
        self.maxNotes = maxNotes
        self.maxWebsites = maxWebsites
        self.maxFiles = maxFiles
        self.maxConversations = maxConversations
    }

}

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

    public func cleanupSnapshots() async {
        await cleanupSnapshots(retention: OfflineSnapshotRetention())
    }

    public func cleanupSnapshots(retention: OfflineSnapshotRetention) async {
        await pruneNoteSnapshots(keepLatest: retention.maxNotes)
        await pruneEntries(entityType: "website", keepLatest: retention.maxWebsites)
        await pruneEntries(entityType: "file", keepLatest: retention.maxFiles)
        await pruneEntries(entityType: "conversation", keepLatest: retention.maxConversations)
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

    private func pruneNoteSnapshots(keepLatest maxCount: Int) async {
        guard maxCount >= 0 else { return }
        do {
            try await performBackgroundTask { context in
                let decoder = JSONDecoder()
                let request = OfflineEntry.fetchRequest()
                request.predicate = NSPredicate(format: "entityType == %@", "note")
                let entries = try context.fetch(request)
                var entriesById: [String: [OfflineEntry]] = [:]
                var lastTouched: [String: Date] = [:]
                for entry in entries {
                    guard let payload = try? decoder.decode(NotePayload.self, from: entry.payload) else {
                        continue
                    }
                    entriesById[payload.id, default: []].append(entry)
                    let modifiedDate = payload.modified.map { Date(timeIntervalSince1970: $0) } ?? entry.updatedAt
                    if let existing = lastTouched[payload.id] {
                        if modifiedDate > existing {
                            lastTouched[payload.id] = modifiedDate
                        }
                    } else {
                        lastTouched[payload.id] = modifiedDate
                    }
                }
                let sortedIds = lastTouched
                    .sorted { $0.value > $1.value }
                    .map(\.key)
                let keepIds = Set(sortedIds.prefix(maxCount))
                for (noteId, noteEntries) in entriesById where !keepIds.contains(noteId) {
                    noteEntries.forEach { context.delete($0) }
                }
            }
        } catch {
            logger.error("OfflineStore prune notes failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func pruneEntries(entityType: String, keepLatest maxCount: Int) async {
        guard maxCount >= 0 else { return }
        do {
            try await performBackgroundTask { context in
                let request = OfflineEntry.fetchRequest()
                request.predicate = NSPredicate(format: "entityType == %@", entityType)
                request.sortDescriptors = [NSSortDescriptor(keyPath: \OfflineEntry.updatedAt, ascending: false)]
                let entries = try context.fetch(request)
                guard entries.count > maxCount else { return }
                let deleteEntries = entries.suffix(from: maxCount)
                deleteEntries.forEach { context.delete($0) }
            }
        } catch {
            logger.error("OfflineStore prune failed for \(entityType, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func performBackgroundTask<T>(
        _ work: @escaping (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            container.performBackgroundTask { context in
                context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                do {
                    let result = try work(context)
                    if context.hasChanges {
                        try context.save()
                    }
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
