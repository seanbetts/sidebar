import Foundation
import sideBarShared
import XCTest
@testable import sideBar

@MainActor
final class NotesWriteQueueExecutorTests: XCTestCase {
    func testExecuteUpdateForwardsQueuedSemanticDocumentBeforeApiCall() async throws {
        let document = NotesSemanticDocument(
            blocks: [
                .paragraph([
                    .init(text: "Queued", marks: [.bold]),
                    .init(text: " body", marks: [])
                ])
            ]
        )

        let api = NotesWriteQueueExecutorAPISpy()
        let store = NotesWriteQueueExecutorStoreSpy()
        let executor = NotesWriteQueueExecutor(api: api, store: store)

        let payload = try JSONEncoder().encode(NoteUpdateRequest(document: document))
        let write = PendingWriteRecord(
            id: UUID(),
            operationType: WriteOperation.update.rawValue,
            entityType: WriteEntityType.note.rawValue,
            entityId: "note-1",
            payload: payload,
            serverSnapshot: nil,
            attempts: 0
        )

        try await executor.execute(write: write)

        XCTAssertEqual(api.updatedDocuments, [document])
        XCTAssertEqual(store.appliedNotes, api.updatedNotes)
    }

    func testExecuteUpdateRoundTripsQueuedSemanticDocumentToStore() async throws {
        let document = NotesSemanticDocument(
            blocks: [
                .paragraph([
                    .init(text: "Round-trip", marks: [.bold]),
                    .init(text: " body", marks: [])
                ])
            ]
        )

        let api = NotesWriteQueueExecutorAPISpy()
        let store = NotesWriteQueueExecutorStoreSpy()
        let executor = NotesWriteQueueExecutor(api: api, store: store)

        try await executor.execute(write: queuedUpdateWrite(document: document, noteId: "note-2"))

        XCTAssertEqual(store.appliedNotes.count, 1)
        XCTAssertEqual(store.appliedNotes[0].document, document)
        XCTAssertEqual(store.appliedNotes[0].plainText, "Round-trip body")
        XCTAssertEqual(store.appliedNotes[0].name, "Round-trip body")
    }

    func testExecuteUpdateDerivesProjectedTitleAndPlainTextFromQueuedSemanticDocument() async throws {
        let document = NotesSemanticDocument(
            blocks: [
                .paragraph([.init(text: "# Queued Title", marks: [])]),
                .paragraph([.init(text: "Body line", marks: [.italic])])
            ]
        )

        let api = NotesWriteQueueExecutorAPISpy()
        let store = NotesWriteQueueExecutorStoreSpy()
        let executor = NotesWriteQueueExecutor(api: api, store: store)

        try await executor.execute(write: queuedUpdateWrite(document: document, noteId: "note-3"))

        XCTAssertEqual(api.updatedDocuments, [document])
        XCTAssertEqual(store.appliedNotes.count, 1)
        XCTAssertEqual(store.appliedNotes[0].name, "Queued Title")
        XCTAssertEqual(store.appliedNotes[0].plainText, "# Queued Title\nBody line")
    }
}

@MainActor
private func queuedUpdateWrite(
    document: NotesSemanticDocument,
    noteId: String
) throws -> PendingWriteRecord {
    let payload = try JSONEncoder().encode(NoteUpdateRequest(document: document))
    return PendingWriteRecord(
        id: UUID(),
        operationType: WriteOperation.update.rawValue,
        entityType: WriteEntityType.note.rawValue,
        entityId: noteId,
        payload: payload,
        serverSnapshot: nil,
        attempts: 0
    )
}

private enum NotesWriteQueueExecutorTestError: Error {
    case forced
}

@MainActor
private final class NotesWriteQueueExecutorStoreSpy: NotesWriteQueueApplying {
    private(set) var appliedNotes: [NotePayload] = []
    private(set) var invalidatedNoteIds: [String] = []
    private(set) var loadTreeCallCount = 0

    func applyEditorUpdate(_ note: NotePayload) {
        appliedNotes.append(note)
    }

    func invalidateNote(id: String) {
        invalidatedNoteIds.append(id)
    }

    func loadTree(force: Bool) async throws {
        _ = force
        loadTreeCallCount += 1
    }
}

@MainActor
private final class NotesWriteQueueExecutorAPISpy: NotesProviding {
    private(set) var updatedDocuments: [NotesSemanticDocument] = []
    private(set) var updatedNotes: [NotePayload] = []

    func listTree() async throws -> FileTree {
        throw NotesWriteQueueExecutorTestError.forced
    }

    func listArchivedTree(limit: Int, offset: Int) async throws -> FileTree {
        _ = limit
        _ = offset
        throw NotesWriteQueueExecutorTestError.forced
    }

    func getNote(id: String) async throws -> NotePayload {
        _ = id
        throw NotesWriteQueueExecutorTestError.forced
    }

    func search(query: String, limit: Int) async throws -> [FileNode] {
        _ = query
        _ = limit
        return []
    }

    func updateNote(id: String, content: String) async throws -> NotePayload {
        let note = NotePayload(
            id: id,
            name: "Queued",
            content: content,
            path: "/\(id).md",
            modified: nil,
            created: nil
        )
        updatedNotes.append(note)
        return note
    }

    func updateNote(id: String, document: NotesSemanticDocument) async throws -> NotePayload {
        updatedDocuments.append(document)
        let plainText = NotesSemanticDocumentProjection.plainText(from: document)
        let note = NotePayload(
            id: id,
            name: NotesSemanticDocumentProjection.title(from: document),
            document: document,
            plainText: plainText,
            path: "/\(id).md",
            modified: nil,
            created: nil
        )
        updatedNotes.append(note)
        return note
    }

    func createNote(request: NoteCreateRequest) async throws -> NotePayload {
        _ = request
        throw NotesWriteQueueExecutorTestError.forced
    }

    func renameNote(id: String, newName: String) async throws -> NotePayload {
        _ = id
        _ = newName
        throw NotesWriteQueueExecutorTestError.forced
    }

    func moveNote(id: String, folder: String) async throws -> NotePayload {
        _ = id
        _ = folder
        throw NotesWriteQueueExecutorTestError.forced
    }

    func archiveNote(id: String, archived: Bool) async throws -> NotePayload {
        _ = id
        _ = archived
        throw NotesWriteQueueExecutorTestError.forced
    }

    func pinNote(id: String, pinned: Bool) async throws -> NotePayload {
        _ = id
        _ = pinned
        throw NotesWriteQueueExecutorTestError.forced
    }

    func updatePinnedOrder(ids: [String]) async throws {
        _ = ids
    }

    func deleteNote(id: String) async throws -> NotePayload {
        _ = id
        throw NotesWriteQueueExecutorTestError.forced
    }

    func createFolder(path: String) async throws {
        _ = path
    }

    func renameFolder(oldPath: String, newName: String) async throws {
        _ = oldPath
        _ = newName
    }

    func moveFolder(oldPath: String, newParent: String) async throws {
        _ = oldPath
        _ = newParent
    }

    func deleteFolder(path: String) async throws {
        _ = path
    }
}
