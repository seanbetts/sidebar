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
            let entry = CacheEntry(context: context)
            entry.key = "expired"
            entry.payload = Data("\"value\"".utf8)
            entry.expiresAt = Date(timeIntervalSince1970: 0)
            entry.createdAt = Date()
            entry.updatedAt = Date()
            entry.typeName = "String"
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
            let entry = CacheEntry(context: context)
            entry.key = "bad"
            entry.payload = Data("not-json".utf8)
            entry.expiresAt = Date().addingTimeInterval(60)
            entry.createdAt = Date()
            entry.updatedAt = Date()
            entry.typeName = "Int"
            try? context.save()
        }

        let fetched: Int? = client.get(key: "bad")

        XCTAssertNil(fetched)
    }

    private func makeContainer() -> NSPersistentContainer {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = "CacheEntry"
        entity.managedObjectClassName = NSStringFromClass(CacheEntry.self)

        let key = NSAttributeDescription()
        key.name = "key"
        key.attributeType = .stringAttributeType
        key.isOptional = false

        let payload = NSAttributeDescription()
        payload.name = "payload"
        payload.attributeType = .binaryDataAttributeType
        payload.isOptional = false

        let expiresAt = NSAttributeDescription()
        expiresAt.name = "expiresAt"
        expiresAt.attributeType = .dateAttributeType
        expiresAt.isOptional = false

        let createdAt = NSAttributeDescription()
        createdAt.name = "createdAt"
        createdAt.attributeType = .dateAttributeType
        createdAt.isOptional = true

        let updatedAt = NSAttributeDescription()
        updatedAt.name = "updatedAt"
        updatedAt.attributeType = .dateAttributeType
        updatedAt.isOptional = true

        let typeName = NSAttributeDescription()
        typeName.name = "typeName"
        typeName.attributeType = .stringAttributeType
        typeName.isOptional = true

        entity.properties = [key, payload, expiresAt, createdAt, updatedAt, typeName]
        model.entities = [entity]

        let container = NSPersistentContainer(name: "CacheModel", managedObjectModel: model)
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
