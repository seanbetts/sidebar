import Foundation
import sideBarShared
import XCTest
@testable import sideBar

@MainActor
final class NotesWriteQueueExecutorTests: XCTestCase {
    func testExecuteUpdateCanonicalizesQueuedNoteContentBeforeApiCall() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }

        let nonCanonical = "- [x] Done"
        let canonical = MarkdownCanonicalizer.canonicalized(nonCanonical)
        XCTAssertNotEqual(canonical, nonCanonical)

        let api = NotesWriteQueueExecutorAPISpy()
        let store = NotesWriteQueueExecutorStoreSpy()
        let executor = NotesWriteQueueExecutor(api: api, store: store)

        let payload = try JSONEncoder().encode(NoteUpdateRequest(content: nonCanonical))
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

        XCTAssertEqual(api.updatedContents, [canonical])
        XCTAssertEqual(store.appliedNotes.map(\.content), [canonical])
    }
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
    private(set) var updatedContents: [String] = []

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
        updatedContents.append(content)
        return NotePayload(
            id: id,
            name: "Queued",
            content: content,
            path: "/\(id).md",
            modified: nil,
            created: nil
        )
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
