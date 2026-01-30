import Foundation
import XCTest
@testable import sideBar

@MainActor
final class OfflineStoreTests: XCTestCase {
    func testSetAndGetValue() {
        let persistence = PersistenceController(inMemory: true)
        let store = OfflineStore(container: persistence.container)

        struct Payload: Codable, Equatable {
            let name: String
        }

        let payload = Payload(name: "Hello")
        store.set(key: "notes/1", entityType: "note", value: payload, lastSyncAt: nil)

        let loaded: Payload? = store.get(key: "notes/1", as: Payload.self)
        XCTAssertEqual(loaded, payload)
    }

    func testGetAllWithPrefix() {
        let persistence = PersistenceController(inMemory: true)
        let store = OfflineStore(container: persistence.container)

        struct Payload: Codable, Equatable {
            let value: String
        }

        store.set(key: "notes/1", entityType: "note", value: Payload(value: "A"), lastSyncAt: nil)
        store.set(key: "notes/2", entityType: "note", value: Payload(value: "B"), lastSyncAt: nil)
        store.set(key: "tasks/1", entityType: "task", value: Payload(value: "C"), lastSyncAt: nil)

        let loaded: [Payload] = store.getAll(keyPrefix: "notes/", as: Payload.self)
        XCTAssertEqual(loaded.count, 2)
    }

    func testLastSyncAtRoundTrip() {
        let persistence = PersistenceController(inMemory: true)
        let store = OfflineStore(container: persistence.container)

        struct Payload: Codable, Equatable {
            let value: String
        }

        let now = Date()
        store.set(key: "tasks/list", entityType: "task", value: Payload(value: "A"), lastSyncAt: now)

        let lastSync = store.lastSyncAt(for: "tasks/list")
        XCTAssertNotNil(lastSync)
    }

    func testRemoveDeletesEntry() {
        let persistence = PersistenceController(inMemory: true)
        let store = OfflineStore(container: persistence.container)

        struct Payload: Codable, Equatable {
            let value: String
        }

        store.set(key: "notes/1", entityType: "note", value: Payload(value: "A"), lastSyncAt: nil)
        store.remove(key: "notes/1")

        let loaded: Payload? = store.get(key: "notes/1", as: Payload.self)
        XCTAssertNil(loaded)
    }
}
