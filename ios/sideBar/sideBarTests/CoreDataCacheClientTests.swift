import CoreData
import XCTest
@testable import sideBar

final class CoreDataCacheClientTests: XCTestCase {
    func testSetAndGetReturnsValue() async throws {
        let container = makeContainer()
        let client = CoreDataCacheClient(container: container)

        client.set(key: "k1", value: "value", ttlSeconds: 60)
        try await Task.sleep(nanoseconds: 200_000_000)

        let fetched: String? = client.get(key: "k1")
        XCTAssertEqual(fetched, "value")
    }

    func testExpiredEntryIsRemoved() {
        let container = makeContainer()
        let client = CoreDataCacheClient(container: container)
        let context = container.viewContext
        context.performAndWait {
            let entry = NSEntityDescription.insertNewObject(
                forEntityName: "CacheEntry",
                into: context
            ) as! NSManagedObject
            entry.setValue("expired", forKey: "key")
            entry.setValue(Data("\"value\"".utf8), forKey: "payload")
            entry.setValue(Date(timeIntervalSince1970: 0), forKey: "expiresAt")
            entry.setValue(Date(), forKey: "createdAt")
            entry.setValue(Date(), forKey: "updatedAt")
            entry.setValue("String", forKey: "typeName")
            try? context.save()
        }

        let fetched: String? = client.get(key: "expired")

        XCTAssertNil(fetched)
        context.performAndWait {
            let request = CacheEntry.fetchRequest()
            request.predicate = NSPredicate(format: "key == %@", "expired")
            let count = (try? context.count(for: request)) ?? 0
            XCTAssertEqual(count, 0)
        }
    }

    func testDecodeFailureReturnsNil() {
        let container = makeContainer()
        let client = CoreDataCacheClient(container: container)
        let context = container.viewContext
        context.performAndWait {
            let entry = NSEntityDescription.insertNewObject(
                forEntityName: "CacheEntry",
                into: context
            ) as! NSManagedObject
            entry.setValue("bad", forKey: "key")
            entry.setValue(Data("not-json".utf8), forKey: "payload")
            entry.setValue(Date().addingTimeInterval(60), forKey: "expiresAt")
            entry.setValue(Date(), forKey: "createdAt")
            entry.setValue(Date(), forKey: "updatedAt")
            entry.setValue("Int", forKey: "typeName")
            try? context.save()
        }

        let fetched: Int? = client.get(key: "bad")

        XCTAssertNil(fetched)
    }

    private func makeContainer() -> NSPersistentContainer {
        let model = PersistenceController.shared.container.persistentStoreCoordinator.managedObjectModel
        let container = NSPersistentContainer(name: "SideBarCache", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]

        let expectation = expectation(description: "store loaded")
        container.loadPersistentStores { _, error in
            XCTAssertNil(error)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        return container
    }
}
