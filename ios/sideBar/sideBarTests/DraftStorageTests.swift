import Foundation
import XCTest
@testable import sideBar

final class DraftStorageTests: XCTestCase {
    func testSaveAndLoadDraft() async throws {
        let persistence = PersistenceController(inMemory: true)
        let storage = DraftStorage(container: persistence.container)

        try await storage.saveDraft(entityType: "note", entityId: "note-1", content: "Hello")

        let draft = try await storage.getDraft(entityType: "note", entityId: "note-1")
        XCTAssertEqual(draft?.content, "Hello")
        XCTAssertNotNil(draft?.savedAt)
        XCTAssertNil(draft?.syncedAt)
    }

    func testMarkSyncedSetsDate() async throws {
        let persistence = PersistenceController(inMemory: true)
        let storage = DraftStorage(container: persistence.container)

        try await storage.saveDraft(entityType: "note", entityId: "note-2", content: "Draft")
        try await storage.markSynced(entityType: "note", entityId: "note-2")

        let draft = try await storage.getDraft(entityType: "note", entityId: "note-2")
        XCTAssertNotNil(draft?.syncedAt)
    }
}
