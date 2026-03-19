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
            description.url = URL(
                fileURLWithPath: NSTemporaryDirectory()
            ).appendingPathComponent(UUID().uuidString)
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
