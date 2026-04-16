import CoreData
import Foundation
import XCTest
@testable import sideBar

@MainActor
final class DraftStorageTests: XCTestCase {
    func testSaveAndLoadDraft() async throws {
        let persistence = PersistenceController(inMemory: true)
        let storage = DraftStorage(container: persistence.container)

        try storage.saveDraft(entityType: "note", entityId: "note-1", content: "Hello")

        let draft = try storage.getDraft(entityType: "note", entityId: "note-1")
        XCTAssertEqual(draft?.content, "Hello")
        XCTAssertEqual(
            draft?.canonicalContent,
            NotesSemanticDocumentCodec.encode(
                NotesSemanticDocumentProjection.document(fromPlainText: "Hello")
            )
        )
        XCTAssertNotNil(draft?.savedAt)
        XCTAssertNil(draft?.syncedAt)
    }

    func testSaveAndLoadSemanticDraftPreservesCanonicalContent() async throws {
        let persistence = PersistenceController(inMemory: true)
        let storage = DraftStorage(container: persistence.container)
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Draft title", marks: [.bold])]),
                .paragraph([.init(text: "Draft body", marks: [.italic])])
            ]
        )
        let canonicalContent = try XCTUnwrap(NotesSemanticDocumentCodec.encode(document))

        try storage.saveDraft(
            entityType: "note",
            entityId: "note-1",
            content: "Draft title\nDraft body",
            canonicalContent: canonicalContent
        )

        let draft = try storage.getDraft(entityType: "note", entityId: "note-1")
        XCTAssertEqual(draft?.content, "Draft title\nDraft body")
        XCTAssertEqual(draft?.canonicalContent, canonicalContent)
    }

    func testMarkSyncedSetsDate() async throws {
        let persistence = PersistenceController(inMemory: true)
        let storage = DraftStorage(container: persistence.container)

        try storage.saveDraft(entityType: "note", entityId: "note-2", content: "Draft")
        try storage.markSynced(entityType: "note", entityId: "note-2")

        let draft = try storage.getDraft(entityType: "note", entityId: "note-2")
        XCTAssertNotNil(draft?.syncedAt)
    }

    func testCleanupSyncedDraftsRemovesOldSyncedEntries() async throws {
        let persistence = PersistenceController(inMemory: true)
        let storage = DraftStorage(container: persistence.container)

        try storage.saveDraft(entityType: "note", entityId: "old-note", content: "Old")
        try storage.saveDraft(entityType: "note", entityId: "new-note", content: "New")
        try storage.markSynced(entityType: "note", entityId: "old-note")
        try storage.markSynced(entityType: "note", entityId: "new-note")

        let context = persistence.container.viewContext
        let request = LocalDraft.fetchRequest()
        let drafts = try context.fetch(request)
        let oldDate = Calendar.current.date(byAdding: .day, value: -10, to: Date()) ?? Date()
        for draft in drafts where draft.entityId == "old-note" {
            draft.syncedAt = oldDate
        }
        try context.save()

        try storage.cleanupSyncedDrafts(olderThan: 7)

        XCTAssertNil(try storage.getDraft(entityType: "note", entityId: "old-note"))
        XCTAssertNotNil(try storage.getDraft(entityType: "note", entityId: "new-note"))
    }

    func testClearAllDraftsRemovesAllDraftEntries() async throws {
        let persistence = PersistenceController(inMemory: true)
        let storage = DraftStorage(container: persistence.container)

        try storage.saveDraft(entityType: "note", entityId: "note-1", content: "Draft one")
        try storage.saveDraft(entityType: "note", entityId: "note-2", content: "Draft two")

        try storage.clearAllDrafts()

        XCTAssertNil(try storage.getDraft(entityType: "note", entityId: "note-1"))
        XCTAssertNil(try storage.getDraft(entityType: "note", entityId: "note-2"))
    }

    func testSaveAndLoadChatDraftUsesChatDraftEntityType() async throws {
        let persistence = PersistenceController(inMemory: true)
        let storage = DraftStorage(container: persistence.container)

        try storage.saveDraft(
            entityType: ChatDraftController.entityType,
            entityId: ChatDraftController.newChatKey,
            content: "Chat draft"
        )

        let draft = try storage.getDraft(
            entityType: ChatDraftController.entityType,
            entityId: ChatDraftController.newChatKey
        )
        XCTAssertEqual(draft?.content, "Chat draft")
    }
}
