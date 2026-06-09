import Foundation
import sideBarShared
import XCTest
@testable import sideBar

@MainActor
final class NotesWriteQueueExecutorTests: XCTestCase {
    func testExecutePinnedOrderForwardsQueuedIdsAndRefreshesTree() async throws {
        let api = NotesWriteQueueExecutorAPISpy()
        let store = NotesWriteQueueExecutorStoreSpy()
        let executor = NotesWriteQueueExecutor(api: api, store: store)
        let payload = try JSONEncoder().encode(PinnedOrderPayload(ids: ["/b.md", "/a.md"]))
        let write = PendingWriteRecord(
            id: UUID(),
            operationType: WriteOperation.reorder.rawValue,
            entityType: WriteEntityType.note.rawValue,
            entityId: nil,
            payload: payload,
            serverSnapshot: nil,
            attempts: 0
        )

        try await executor.execute(write: write)

        XCTAssertEqual(api.updatedPinnedOrderIDs, [["/b.md", "/a.md"]])
        XCTAssertEqual(store.loadTreeForceValues, [true])
    }

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
                .init(type: .title, content: [.init(text: "Round-trip body", marks: [])]),
                .paragraph([.init(text: "Queued follow-up", marks: [.bold])])
            ]
        )

        let api = NotesWriteQueueExecutorAPISpy()
        let store = NotesWriteQueueExecutorStoreSpy()
        let executor = NotesWriteQueueExecutor(api: api, store: store)

        try await executor.execute(write: queuedUpdateWrite(document: document, noteId: "note-2"))

        XCTAssertEqual(store.appliedNotes.count, 1)
        XCTAssertEqual(store.appliedNotes[0].document, document)
        XCTAssertEqual(store.appliedNotes[0].plainText, "Round-trip body\nQueued follow-up")
        XCTAssertEqual(store.appliedNotes[0].name, "Round-trip body")
    }

    func testExecuteUpdateDerivesProjectedTitleAndPlainTextFromQueuedSemanticDocument() async throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Queued Title", marks: [])]),
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
        XCTAssertEqual(store.appliedNotes[0].plainText, "Queued Title\nBody line")
    }

    func testExecuteUpdatePrefersLocalQueuedNoteWhenServerSnapshotIsStale() async throws {
        let document = NotesSemanticDocument(
            blocks: [
                .paragraph([.init(text: "Local draft wins", marks: [])])
            ]
        )
        let api = NotesWriteQueueExecutorAPISpy()
        let store = NotesWriteQueueExecutorStoreSpy()
        let executor = NotesWriteQueueExecutor(api: api, store: store)
        let serverSnapshot = ServerSnapshot(
            entityType: .note,
            entityId: "note-4",
            capturedAt: Date(),
            payload: .note(
                NoteSnapshot(
                    modified: 100,
                    name: "Server",
                    path: "/note-4.md",
                    pinned: nil,
                    pinnedOrder: nil,
                    archived: nil
                )
            )
        )
        let write = try queuedUpdateWrite(
            document: document,
            noteId: "note-4",
            serverSnapshot: serverSnapshot
        )

        try await executor.execute(write: write)

        XCTAssertEqual(api.updatedDocuments, [document])
        XCTAssertEqual(store.appliedNotes, api.updatedNotes)
    }

    func testExecuteMovePrefersLocalQueuedMoveWhenServerSnapshotIsStale() async throws {
        let api = NotesWriteQueueExecutorAPISpy()
        api.fetchedNote = NotePayload(
            id: "note-5",
            name: "Server",
            content: "Server copy",
            path: "/folder/note-5.md",
            modified: 200,
            created: nil
        )
        let store = NotesWriteQueueExecutorStoreSpy()
        let executor = NotesWriteQueueExecutor(api: api, store: store)
        let serverSnapshot = ServerSnapshot(
            entityType: .note,
            entityId: "note-5",
            capturedAt: Date(),
            payload: .note(
                NoteSnapshot(
                    modified: 100,
                    name: "Server",
                    path: "/folder/note-5.md",
                    pinned: nil,
                    pinnedOrder: nil,
                    archived: nil
                )
            )
        )
        let write = try queuedMoveWrite(
            noteId: "note-5",
            folder: "archive",
            serverSnapshot: serverSnapshot
        )

        try await executor.execute(write: write)

        XCTAssertEqual(api.movedNotes.count, 1)
        XCTAssertEqual(api.movedNotes.first?.id, "note-5")
        XCTAssertEqual(api.movedNotes.first?.folder, "archive")
        XCTAssertEqual(store.appliedNotes, api.moveResults)
    }
}

@MainActor
private func queuedUpdateWrite(
    document: NotesSemanticDocument,
    noteId: String,
    serverSnapshot: ServerSnapshot? = nil
) throws -> PendingWriteRecord {
    let payload = try JSONEncoder().encode(NoteUpdateRequest(document: document))
    return PendingWriteRecord(
        id: UUID(),
        operationType: WriteOperation.update.rawValue,
        entityType: WriteEntityType.note.rawValue,
        entityId: noteId,
        payload: payload,
        serverSnapshot: try serverSnapshot.map { try JSONEncoder().encode($0) },
        attempts: 0
    )
}

@MainActor
private func queuedMoveWrite(
    noteId: String,
    folder: String,
    serverSnapshot: ServerSnapshot? = nil
) throws -> PendingWriteRecord {
    let payload = try JSONEncoder().encode(MoveRequest(folder: folder))
    return PendingWriteRecord(
        id: UUID(),
        operationType: WriteOperation.move.rawValue,
        entityType: WriteEntityType.note.rawValue,
        entityId: noteId,
        payload: payload,
        serverSnapshot: try serverSnapshot.map { try JSONEncoder().encode($0) },
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
    private(set) var loadTreeForceValues: [Bool] = []

    func applyEditorUpdate(_ note: NotePayload) {
        appliedNotes.append(note)
    }

    func invalidateNote(id: String) {
        invalidatedNoteIds.append(id)
    }

    func loadTree(force: Bool) async throws {
        loadTreeForceValues.append(force)
    }
}

@MainActor
private final class NotesWriteQueueExecutorAPISpy: NotesProviding {
    var fetchedNote: NotePayload?
    private(set) var updatedDocuments: [NotesSemanticDocument] = []
    private(set) var updatedNotes: [NotePayload] = []
    private(set) var movedNotes: [(id: String, folder: String)] = []
    private(set) var moveResults: [NotePayload] = []
    private(set) var updatedPinnedOrderIDs: [[String]] = []

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
        guard let fetchedNote else {
            throw NotesWriteQueueExecutorTestError.forced
        }
        return fetchedNote
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
        movedNotes.append((id, folder))
        let note = NotePayload(
            id: id,
            name: "Moved",
            content: "Moved body",
            path: "/\(folder)/\(id).md",
            modified: nil,
            created: nil
        )
        moveResults.append(note)
        return note
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
        updatedPinnedOrderIDs.append(ids)
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
