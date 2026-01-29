import Foundation
import XCTest
@testable import sideBar

@MainActor
final class DraftStorageTests: XCTestCase {
    func testSaveAndLoadDraft() throws {
        let persistence = PersistenceController(inMemory: true)
        let storage = DraftStorage(container: persistence.container)

        try storage.saveDraft(entityType: "note", entityId: "note-1", content: "Hello")

        let draft = try storage.getDraft(entityType: "note", entityId: "note-1")
        XCTAssertEqual(draft?.content, "Hello")
        XCTAssertNotNil(draft?.savedAt)
        XCTAssertNil(draft?.syncedAt)
    }

    func testMarkSyncedSetsDate() throws {
        let persistence = PersistenceController(inMemory: true)
        let storage = DraftStorage(container: persistence.container)

        try storage.saveDraft(entityType: "note", entityId: "note-2", content: "Draft")
        try storage.markSynced(entityType: "note", entityId: "note-2")

        let draft = try storage.getDraft(entityType: "note", entityId: "note-2")
        XCTAssertNotNil(draft?.syncedAt)
    }
}
