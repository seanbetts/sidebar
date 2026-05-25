import CoreData
import XCTest
@testable import sideBar

@MainActor
final class PersistenceControllerTests: XCTestCase {
    func testCacheAndOfflineEntriesDeclareUniqueKeyConstraints() {
        let model = PersistenceController(inMemory: true).container.managedObjectModel
        let cacheEntity = model.entitiesByName["CacheEntry"]
        let offlineEntity = model.entitiesByName["OfflineEntry"]

        XCTAssertEqual(cacheEntity?.uniquenessConstraints as? [[String]], [["key"]])
        XCTAssertEqual(offlineEntity?.uniquenessConstraints as? [[String]], [["key"]])
    }

    func testRemoveDuplicateEntriesKeepsNewestCacheAndOfflineEntryPerKey() throws {
        let container = Self.makeInMemoryContainer(
            model: try Self.makeModelWithoutCacheAndOfflineConstraints()
        )
        try Self.loadStores(container)
        let context = container.viewContext
        let olderDate = Date(timeIntervalSince1970: 100)
        let newerDate = Date(timeIntervalSince1970: 200)

        let olderCache = NSEntityDescription.insertNewObject(
            forEntityName: "CacheEntry",
            into: context
        )
        let olderCacheEntry = try XCTUnwrap(olderCache as? CacheEntry)
        olderCacheEntry.key = "cache-key"
        olderCacheEntry.payload = Data("older-cache".utf8)
        olderCacheEntry.updatedAt = olderDate

        let newerCache = NSEntityDescription.insertNewObject(
            forEntityName: "CacheEntry",
            into: context
        )
        let newerCacheEntry = try XCTUnwrap(newerCache as? CacheEntry)
        newerCacheEntry.key = "cache-key"
        newerCacheEntry.payload = Data("newer-cache".utf8)
        newerCacheEntry.updatedAt = newerDate

        let olderOffline = OfflineEntry.insertNew(in: context)
        olderOffline.id = UUID()
        olderOffline.key = "offline-key"
        olderOffline.entityType = "note"
        olderOffline.payload = Data("older-offline".utf8)
        olderOffline.updatedAt = olderDate

        let newerOffline = OfflineEntry.insertNew(in: context)
        newerOffline.id = UUID()
        newerOffline.key = "offline-key"
        newerOffline.entityType = "note"
        newerOffline.payload = Data("newer-offline".utf8)
        newerOffline.updatedAt = newerDate

        try context.save()
        try PersistenceController.removeDuplicateEntries(in: context)

        let cacheRequest = CacheEntry.fetchRequest()
        cacheRequest.predicate = NSPredicate(format: "key == %@", "cache-key")
        let cacheEntries = try context.fetch(cacheRequest)
        XCTAssertEqual(cacheEntries.count, 1)
        XCTAssertEqual(cacheEntries.first?.payload, Data("newer-cache".utf8))
        XCTAssertEqual(cacheEntries.first?.updatedAt, newerDate)

        let offlineRequest = OfflineEntry.fetchRequest()
        offlineRequest.predicate = NSPredicate(format: "key == %@", "offline-key")
        let offlineEntries = try context.fetch(offlineRequest)
        XCTAssertEqual(offlineEntries.count, 1)
        XCTAssertEqual(offlineEntries.first?.payload, Data("newer-offline".utf8))
        XCTAssertEqual(offlineEntries.first?.updatedAt, newerDate)
    }

    func testLoadStoresWithRecoveryCleansDuplicateEntriesAfterStoreLoad() throws {
        let container = NSPersistentContainer(name: "SideBarCache")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.url = URL(fileURLWithPath: "/dev/null/\(UUID().uuidString)")
        container.persistentStoreDescriptions = [description]
        let olderDate = Date(timeIntervalSince1970: 100)
        let newerDate = Date(timeIntervalSince1970: 200)

        let state = PersistenceController.loadStoresWithRecovery(
            inMemory: false,
            container: container,
            storeLoader: { container in
                try Self.loadStores(container)

                let context = container.viewContext
                let olderCache = NSEntityDescription.insertNewObject(
                    forEntityName: "CacheEntry",
                    into: context
                )
                let olderCacheEntry = try XCTUnwrap(olderCache as? CacheEntry)
                olderCacheEntry.key = "cache-key"
                olderCacheEntry.payload = Data("older-cache".utf8)
                olderCacheEntry.updatedAt = olderDate

                let newerCache = NSEntityDescription.insertNewObject(
                    forEntityName: "CacheEntry",
                    into: context
                )
                let newerCacheEntry = try XCTUnwrap(newerCache as? CacheEntry)
                newerCacheEntry.key = "cache-key"
                newerCacheEntry.payload = Data("newer-cache".utf8)
                newerCacheEntry.updatedAt = newerDate
            },
            storeResetter: { _, _ in },
            logger: { _ in }
        )

        XCTAssertEqual(state, .none)

        let request = CacheEntry.fetchRequest()
        request.predicate = NSPredicate(format: "key == %@", "cache-key")
        let cacheEntries = try container.viewContext.fetch(request)
        XCTAssertEqual(cacheEntries.count, 1)
        XCTAssertEqual(cacheEntries.first?.payload, Data("newer-cache".utf8))
    }

    func testRecoveryStateIsNoneWhenLoadSucceedsImmediately() {
        var loadCallCount = 0
        var didResetStore = false

        let state = PersistenceController.loadStoresWithRecovery(
            inMemory: false,
            container: Self.makeStubContainer(),
            storeLoader: { _ in loadCallCount += 1 },
            storeResetter: { _, _ in didResetStore = true },
            logger: { _ in }
        )

        XCTAssertEqual(state, .none)
        XCTAssertEqual(loadCallCount, 1)
        XCTAssertFalse(didResetStore)
    }

    func testMigrationErrorTriggersStoreResetRecovery() {
        var loadCallCount = 0
        var resetCallCount = 0

        let state = PersistenceController.loadStoresWithRecovery(
            inMemory: false,
            container: Self.makeStubContainer(),
            storeLoader: { _ in
                loadCallCount += 1
                if loadCallCount == 1 {
                    throw NSError(
                        domain: NSCocoaErrorDomain,
                        code: NSMigrationMissingMappingModelError
                    )
                }
            },
            storeResetter: { _, _ in resetCallCount += 1 },
            logger: { _ in }
        )

        XCTAssertEqual(state, .recoveredFromStoreReset)
        XCTAssertEqual(loadCallCount, 2)
        XCTAssertEqual(resetCallCount, 1)
    }

    func testCorruptionResetFailureFallsBackToInMemoryStore() {
        var loadCallCount = 0
        var resetCallCount = 0
        var didUseInMemoryFallback = false

        let state = PersistenceController.loadStoresWithRecovery(
            inMemory: false,
            container: Self.makeStubContainer(),
            storeLoader: { container in
                loadCallCount += 1
                if loadCallCount == 1 {
                    throw NSError(
                        domain: NSCocoaErrorDomain,
                        code: NSPersistentStoreIncompatibleVersionHashError
                    )
                }
                if container.persistentStoreDescriptions.first?.type == NSInMemoryStoreType {
                    didUseInMemoryFallback = true
                }
            },
            storeResetter: { _, _ in
                resetCallCount += 1
                throw NSError(domain: NSCocoaErrorDomain, code: NSPersistentStoreOpenError)
            },
            logger: { _ in }
        )

        XCTAssertEqual(state, .recoveredWithInMemoryFallback)
        XCTAssertEqual(loadCallCount, 2)
        XCTAssertEqual(resetCallCount, 1)
        XCTAssertTrue(didUseInMemoryFallback)
    }

    func testShouldAttemptStoreResetRecognizesMigrationAndCorruptionErrors() {
        let migrationError = NSError(
            domain: NSCocoaErrorDomain,
            code: NSMigrationMissingSourceModelError
        )
        XCTAssertTrue(PersistenceController.shouldAttemptStoreReset(for: migrationError))

        let sqliteCorruption = NSError(domain: NSSQLiteErrorDomain, code: 11)
        let wrappedError = NSError(
            domain: NSCocoaErrorDomain,
            code: NSPersistentStoreOperationError,
            userInfo: [NSUnderlyingErrorKey: sqliteCorruption]
        )
        XCTAssertTrue(PersistenceController.shouldAttemptStoreReset(for: wrappedError))

        let unrelatedError = NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
        XCTAssertFalse(PersistenceController.shouldAttemptStoreReset(for: unrelatedError))
    }

    private static func makeStubContainer() -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "SideBarCache")
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        let description = NSPersistentStoreDescription(url: storeURL)
        description.type = NSSQLiteStoreType
        container.persistentStoreDescriptions = [description]
        return container
    }

    private static func makeInMemoryContainer(model: NSManagedObjectModel) -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "SideBarCache", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.url = URL(fileURLWithPath: "/dev/null/\(UUID().uuidString)")
        container.persistentStoreDescriptions = [description]
        return container
    }

    private static func makeModelWithoutCacheAndOfflineConstraints() throws -> NSManagedObjectModel {
        let copiedModel = PersistenceController(inMemory: true).container.managedObjectModel.copy()
        let model = try XCTUnwrap(copiedModel as? NSManagedObjectModel)
        model.entitiesByName["CacheEntry"]?.uniquenessConstraints = []
        model.entitiesByName["OfflineEntry"]?.uniquenessConstraints = []
        return model
    }

    private static func loadStores(_ container: NSPersistentContainer) throws {
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
}
