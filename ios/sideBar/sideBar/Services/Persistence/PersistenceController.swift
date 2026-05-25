import CoreData
import Foundation
import os

/// Configures Core Data persistence for the app.
public final class PersistenceController {
    /// Indicates whether persistent-store loading required recovery steps.
    public enum RecoveryState: String, Equatable {
        case none
        case recoveredFromStoreReset
        case recoveredWithInMemoryFallback
    }

    typealias StoreLoader = (NSPersistentContainer) throws -> Void
    typealias StoreResetter = (NSPersistentContainer, URL) throws -> Void
    typealias RecoveryLogger = (String) -> Void

    nonisolated private static let logger = Logger(subsystem: "sideBar", category: "Persistence")

    public static let shared = PersistenceController()

    public let container: NSPersistentContainer
    public let recoveryState: RecoveryState

    public convenience init(inMemory: Bool = false) {
        self.init(
            inMemory: inMemory,
            containerFactory: { NSPersistentContainer(name: "SideBarCache") },
            storeLoader: Self.loadPersistentStoresSynchronously,
            storeResetter: Self.resetPersistentStore,
            logger: Self.logRecoveryEvent
        )
    }

    init(
        inMemory: Bool,
        containerFactory: () -> NSPersistentContainer,
        storeLoader: @escaping StoreLoader,
        storeResetter: @escaping StoreResetter,
        logger: @escaping RecoveryLogger
    ) {
        container = containerFactory()
        Self.configureStoreOptions(for: container)

        let resolvedState = Self.loadStoresWithRecovery(
            inMemory: inMemory,
            container: container,
            storeLoader: storeLoader,
            storeResetter: storeResetter,
            logger: logger
        )
        recoveryState = resolvedState

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    nonisolated static func shouldAttemptStoreReset(for error: NSError) -> Bool {
        for currentError in errorChain(from: error) {
            if isMigrationError(currentError) || isCorruptionError(currentError) {
                return true
            }
        }
        return false
    }

    nonisolated static func loadStoresWithRecovery(
        inMemory: Bool,
        container: NSPersistentContainer,
        storeLoader: StoreLoader,
        storeResetter: StoreResetter,
        logger: RecoveryLogger
    ) -> RecoveryState {
        if inMemory {
            configureInMemoryStore(for: container)
        }

        do {
            try storeLoader(container)
            prepareLoadedStore(in: container, logger: logger)
            return .none
        } catch {
            let loadError = error as NSError
            logger("Initial persistent store load failed: \(loadError)")

            if !inMemory,
               shouldAttemptStoreReset(for: loadError),
               let storeURL = container.persistentStoreDescriptions.first?.url {
                do {
                    try storeResetter(container, storeURL)
                    try storeLoader(container)
                    prepareLoadedStore(in: container, logger: logger)
                    logger("Recovered Core Data by resetting persistent store at \(storeURL.path)")
                    return .recoveredFromStoreReset
                } catch {
                    let resetError = error as NSError
                    logger("Persistent store reset recovery failed: \(resetError)")
                }
            }

            if !inMemory {
                do {
                    configureInMemoryStore(for: container)
                    try storeLoader(container)
                    prepareLoadedStore(in: container, logger: logger)
                    logger("Recovered Core Data by switching to in-memory fallback store")
                    return .recoveredWithInMemoryFallback
                } catch {
                    let fallbackError = error as NSError
                    logger("In-memory fallback recovery failed: \(fallbackError)")
                }
            }

            fatalError("Unrecoverable Core Data load failure")
        }
    }

    nonisolated private static func configureStoreOptions(for container: NSPersistentContainer) {
        #if os(iOS)
        container.persistentStoreDescriptions.forEach { description in
            description.setOption(
                FileProtectionType.completeUntilFirstUserAuthentication as NSObject,
                forKey: NSPersistentStoreFileProtectionKey
            )
        }
        #endif
    }

    nonisolated private static func configureInMemoryStore(for container: NSPersistentContainer) {
        container.persistentStoreDescriptions.forEach { description in
            description.type = NSInMemoryStoreType
            description.url = URL(fileURLWithPath: "/dev/null/\(UUID().uuidString)")
        }
    }

    nonisolated private static func prepareLoadedStore(
        in container: NSPersistentContainer,
        logger: RecoveryLogger
    ) {
        let context = container.viewContext
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        do {
            try removeDuplicateEntries(in: context)
        } catch {
            logger("Duplicate cache/offline cleanup failed: \(error as NSError)")
        }
    }

    nonisolated static func removeDuplicateEntries(in context: NSManagedObjectContext) throws {
        var capturedError: Error?
        context.performAndWait {
            do {
                try removeDuplicates(entityName: "CacheEntry", keyName: "key", dateName: "updatedAt", in: context)
                try removeDuplicates(entityName: "OfflineEntry", keyName: "key", dateName: "updatedAt", in: context)
            } catch {
                capturedError = error
            }
        }
        if let capturedError {
            throw capturedError
        }
    }

    nonisolated private static func removeDuplicates(
        entityName: String,
        keyName: String,
        dateName: String,
        in context: NSManagedObjectContext
    ) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.sortDescriptors = [
            NSSortDescriptor(key: keyName, ascending: true),
            NSSortDescriptor(key: dateName, ascending: false)
        ]
        let entries = try context.fetch(request)
        let groupedEntries = Dictionary(grouping: entries) { entry in
            entry.value(forKey: keyName) as? String ?? ""
        }
        for duplicates in groupedEntries.values where duplicates.count > 1 {
            let sortedDuplicates = duplicates.sorted { first, second in
                let firstDate = first.value(forKey: dateName) as? Date ?? .distantPast
                let secondDate = second.value(forKey: dateName) as? Date ?? .distantPast
                return firstDate > secondDate
            }
            for duplicate in sortedDuplicates.dropFirst() {
                context.delete(duplicate)
            }
        }
        context.processPendingChanges()
        if context.hasChanges {
            try context.save()
        }
    }

    nonisolated private static func loadPersistentStoresSynchronously(container: NSPersistentContainer) throws {
        let storeCount = max(1, container.persistentStoreDescriptions.count)
        let lock = NSLock()
        var remaining = storeCount
        var capturedError: Error?
        let semaphore = DispatchSemaphore(value: 0)

        container.loadPersistentStores { _, error in
            lock.lock()
            if capturedError == nil, let error {
                capturedError = error
            }
            remaining -= 1
            let shouldSignal = remaining == 0
            lock.unlock()

            if shouldSignal {
                semaphore.signal()
            }
        }

        semaphore.wait()
        if let capturedError {
            throw capturedError
        }
    }

    nonisolated private static func resetPersistentStore(
        container: NSPersistentContainer,
        storeURL: URL
    ) throws {
        let coordinator = container.persistentStoreCoordinator
        if FileManager.default.fileExists(atPath: storeURL.path) {
            try coordinator.destroyPersistentStore(at: storeURL, type: .sqlite, options: nil)
        }
        removeSQLiteSidecars(for: storeURL)
    }

    nonisolated private static func removeSQLiteSidecars(for storeURL: URL) {
        let sidecars = [
            URL(fileURLWithPath: "\(storeURL.path)-shm"),
            URL(fileURLWithPath: "\(storeURL.path)-wal")
        ]
        for sidecar in sidecars where FileManager.default.fileExists(atPath: sidecar.path) {
            try? FileManager.default.removeItem(at: sidecar)
        }
    }

    nonisolated private static func logRecoveryEvent(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    nonisolated private static func errorChain(from error: NSError) -> [NSError] {
        var errors: [NSError] = [error]
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            errors.append(contentsOf: errorChain(from: underlying))
        }
        return errors
    }

    nonisolated private static func isMigrationError(_ error: NSError) -> Bool {
        guard error.domain == NSCocoaErrorDomain else { return false }
        let migrationCodes: Set<Int> = [
            NSMigrationError,
            NSMigrationCancelledError,
            NSMigrationMissingSourceModelError,
            NSMigrationMissingMappingModelError,
            NSMigrationManagerSourceStoreError,
            NSMigrationManagerDestinationStoreError,
            NSPersistentStoreIncompatibleVersionHashError,
            NSPersistentStoreIncompatibleSchemaError
        ]
        return migrationCodes.contains(error.code)
    }

    nonisolated private static func isCorruptionError(_ error: NSError) -> Bool {
        if error.domain == NSCocoaErrorDomain {
            let coreDataCorruptionCodes: Set<Int> = [
                NSPersistentStoreOpenError,
                NSPersistentStoreTimeoutError,
                NSPersistentStoreOperationError,
                NSPersistentStoreIncompatibleVersionHashError,
                NSPersistentStoreIncompatibleSchemaError
            ]
            if coreDataCorruptionCodes.contains(error.code) {
                return true
            }
        }

        if error.domain == NSSQLiteErrorDomain {
            let sqliteCorruptionCodes: Set<Int> = [
                11, // SQLITE_CORRUPT
                26 // SQLITE_NOTADB
            ]
            return sqliteCorruptionCodes.contains(error.code)
        }

        return false
    }
}
