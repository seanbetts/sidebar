import XCTest
@testable import sideBar

@MainActor
final class NotesViewModelTests: XCTestCase {
    func testLoadTreeUsesCacheOnFailure() async {
        let cachedTree = FileTree(children: [
            FileNode(
                name: "Cached",
                path: "/cached",
                type: .file,
                size: nil,
                modified: nil,
                children: nil,
                expanded: nil,
                pinned: nil,
                pinnedOrder: nil,
                archived: nil,
                folderMarker: nil
            )
        ])
        let cache = InMemoryCacheClient()
        cache.set(key: CacheKeys.notesTree, value: cachedTree, ttlSeconds: 60)

        let api = MockNotesAPI(listTreeResult: .failure(MockError.forced))
        let viewModel = NotesViewModel(api: api, cache: cache)

        await viewModel.loadTree()

        XCTAssertEqual(viewModel.tree?.children.first?.name, "Cached")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadTreeCachesFreshData() async {
        let freshTree = FileTree(children: [
            FileNode(
                name: "Fresh",
                path: "/fresh",
                type: .file,
                size: nil,
                modified: nil,
                children: nil,
                expanded: nil,
                pinned: nil,
                pinnedOrder: nil,
                archived: nil,
                folderMarker: nil
            )
        ])
        let cache = InMemoryCacheClient()
        let api = MockNotesAPI(listTreeResult: .success(freshTree))
        let viewModel = NotesViewModel(api: api, cache: cache)

        await viewModel.loadTree()

        let cached: FileTree? = cache.get(key: CacheKeys.notesTree)
        XCTAssertEqual(cached?.children.first?.name, "Fresh")
    }

    func testApplyRealtimeEventClearsSelectionOnDelete() async {
        let tree = FileTree(children: [
            FileNode(
                name: "Note.md",
                path: "note-id",
                type: .file,
                size: nil,
                modified: nil,
                children: nil,
                expanded: nil,
                pinned: nil,
                pinnedOrder: nil,
                archived: nil,
                folderMarker: nil
            )
        ])
        let note = NotePayload(
            id: "note-id",
            name: "Note.md",
            content: "Hello",
            path: "note-id",
            modified: nil
        )
        let cache = InMemoryCacheClient()
        let api = MockNotesAPI(
            listTreeResult: .success(tree),
            getNoteResult: .success(note)
        )
        let viewModel = NotesViewModel(api: api, cache: cache)

        await viewModel.selectNote(id: "note-id")
        XCTAssertEqual(viewModel.selectedNoteId, "note-id")

        let payload = RealtimePayload(
            eventType: .delete,
            table: RealtimeTable.notes,
            schema: "public",
            record: nil,
            oldRecord: NoteRealtimeRecord(
                id: "note-id",
                title: "Note",
                content: nil,
                metadata: nil,
                updatedAt: nil,
                deletedAt: nil
            )
        )

        await viewModel.applyRealtimeEvent(payload)

        XCTAssertNil(viewModel.selectedNoteId)
        XCTAssertNil(viewModel.activeNote)
    }
}

private enum MockError: Error {
    case forced
}

private struct MockNotesAPI: NotesProviding {
    let listTreeResult: Result<FileTree, Error>
    let getNoteResult: Result<NotePayload, Error>

    init(
        listTreeResult: Result<FileTree, Error>,
        getNoteResult: Result<NotePayload, Error> = .failure(MockError.forced)
    ) {
        self.listTreeResult = listTreeResult
        self.getNoteResult = getNoteResult
    }

    func listTree() async throws -> FileTree {
        try listTreeResult.get()
    }

    func getNote(id: String) async throws -> NotePayload {
        _ = id
        return try getNoteResult.get()
    }

    func search(query: String, limit: Int) async throws -> [FileNode] {
        _ = query
        _ = limit
        return []
    }
}
