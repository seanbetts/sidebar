import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class ChatContextProviderTests: XCTestCase {
    func testNotesContextProviderRefreshReloadsVisibleNoteDetailForUpdatedNote() async throws {
        let initial = NotePayload(
            id: "note-1",
            name: "Open.md",
            content: "Initial",
            path: "note-1",
            modified: 100,
            created: nil
        )
        let refreshed = NotePayload(
            id: "note-1",
            name: "Open.md",
            content: "Refreshed",
            path: "note-1",
            modified: 200,
            created: nil
        )
        let cache = InMemoryCacheClient()
        let store = NotesStore(
            api: SequencedContextNotesAPI(
                tree: FileTree(children: []),
                noteResults: [
                    .success(initial),
                    .success(refreshed)
                ]
            ),
            cache: cache
        )
        let provider = NotesContextProvider(cache: cache, notesStore: store)

        try await store.loadNote(id: "note-1")
        XCTAssertEqual(store.activeNote?.content, "Initial")

        try await provider.refresh(.notes(noteId: "note-1"))

        XCTAssertEqual(store.activeNote?.content, "Refreshed")
    }
}

private final class SequencedContextNotesAPI: NotesProviding {
    let tree: FileTree
    private var noteResults: [Result<NotePayload, Error>]

    init(
        tree: FileTree,
        noteResults: [Result<NotePayload, Error>]
    ) {
        self.tree = tree
        self.noteResults = noteResults
    }

    func listTree() async throws -> FileTree {
        tree
    }

    func listArchivedTree(limit: Int, offset: Int) async throws -> FileTree {
        _ = limit
        _ = offset
        return tree
    }

    func getNote(id: String) async throws -> NotePayload {
        _ = id
        guard !noteResults.isEmpty else {
            throw NotesStoreTestsSupport.MockError.forced
        }
        return try noteResults.removeFirst().get()
    }

    func search(query: String, limit: Int) async throws -> [FileNode] {
        _ = query
        _ = limit
        return []
    }

    func updateNote(id: String, content: String) async throws -> NotePayload {
        _ = id
        _ = content
        throw NotesStoreTestsSupport.MockError.forced
    }

    func updateNote(id: String, document: NotesSemanticDocument) async throws -> NotePayload {
        _ = id
        _ = document
        throw NotesStoreTestsSupport.MockError.forced
    }

    func createNote(request: NoteCreateRequest) async throws -> NotePayload {
        _ = request
        throw NotesStoreTestsSupport.MockError.forced
    }

    func renameNote(id: String, newName: String) async throws -> NotePayload {
        _ = id
        _ = newName
        throw NotesStoreTestsSupport.MockError.forced
    }

    func moveNote(id: String, folder: String) async throws -> NotePayload {
        _ = id
        _ = folder
        throw NotesStoreTestsSupport.MockError.forced
    }

    func archiveNote(id: String, archived: Bool) async throws -> NotePayload {
        _ = id
        _ = archived
        throw NotesStoreTestsSupport.MockError.forced
    }

    func pinNote(id: String, pinned: Bool) async throws -> NotePayload {
        _ = id
        _ = pinned
        throw NotesStoreTestsSupport.MockError.forced
    }

    func updatePinnedOrder(ids: [String]) async throws {
        _ = ids
    }

    func deleteNote(id: String) async throws -> NotePayload {
        _ = id
        throw NotesStoreTestsSupport.MockError.forced
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
