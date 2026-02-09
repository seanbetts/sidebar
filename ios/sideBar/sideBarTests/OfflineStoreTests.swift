import CoreData
import Foundation
import XCTest
@testable import sideBar

@MainActor
final class OfflineStoreTests: XCTestCase {
    func testSetAndGetValue() async {
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

    func testGetAllWithPrefix() async {
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

    func testLastSyncAtRoundTrip() async {
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

    func testRemoveDeletesEntry() async {
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

    func testClearAllSnapshotsDeletesAllEntries() async {
        let persistence = PersistenceController(inMemory: true)
        let store = OfflineStore(container: persistence.container)

        struct Payload: Codable, Equatable {
            let value: String
        }

        store.set(key: "notes/1", entityType: "note", value: Payload(value: "A"), lastSyncAt: nil)
        store.set(key: "tasks/1", entityType: "task", value: Payload(value: "B"), lastSyncAt: nil)

        store.clearAllSnapshots()

        let note: Payload? = store.get(key: "notes/1", as: Payload.self)
        let task: Payload? = store.get(key: "tasks/1", as: Payload.self)
        XCTAssertNil(note)
        XCTAssertNil(task)
    }

    func testCleanupSnapshotsPrunesNoteEntries() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = OfflineStore(container: persistence.container)

        let notes = [
            NotePayload(id: "note-1", name: "One", content: "A", path: "/one.md", modified: 1, created: nil),
            NotePayload(id: "note-2", name: "Two", content: "B", path: "/two.md", modified: 2, created: nil),
            NotePayload(id: "note-3", name: "Three", content: "C", path: "/three.md", modified: 3, created: nil)
        ]

        for note in notes {
            store.set(key: CacheKeys.note(id: note.id), entityType: "note", value: note, lastSyncAt: nil)
            store.set(key: CacheKeys.note(id: note.path), entityType: "note", value: note, lastSyncAt: nil)
        }

        await store.cleanupSnapshots(retention: OfflineSnapshotRetention(maxNotes: 2))

        let request = OfflineEntry.fetchRequest()
        request.predicate = NSPredicate(format: "entityType == %@", "note")
        let entries = try persistence.container.viewContext.fetch(request)
        let decoded = entries.compactMap { try? JSONDecoder().decode(NotePayload.self, from: $0.payload) }
        let remainingIds = Set(decoded.map(\.id))

        XCTAssertEqual(remainingIds, Set(["note-2", "note-3"]))
        XCTAssertEqual(entries.count, 4)
    }
}
