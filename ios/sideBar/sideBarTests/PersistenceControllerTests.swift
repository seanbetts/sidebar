import CoreData
import XCTest
@testable import sideBar

@MainActor
final class PersistenceControllerTests: XCTestCase {
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
                if container.persistentStoreDescriptions.first?.url?.path == "/dev/null" {
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
}
