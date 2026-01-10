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

    func testLoadTreeInjectsScratchpad() async {
        let tree = FileTree(children: [
            FileNode(
                name: "Note",
                path: "/note",
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
        let api = MockNotesAPI(listTreeResult: .success(tree))
        let scratchpad = ScratchpadResponse(
            id: "scratch-id",
            title: "✏️ Scratchpad",
            content: "# ✏️ Scratchpad\n\n",
            updatedAt: "2026-01-02T10:00:00Z"
        )
        let scratchpadAPI = MockScratchpadAPI(result: .success(scratchpad))
        let viewModel = NotesViewModel(api: api, cache: cache, scratchpadAPI: scratchpadAPI)

        await viewModel.loadTree()

        XCTAssertEqual(viewModel.tree?.children.first?.path, "scratch-id")
    }
}

private enum MockError: Error {
    case forced
}

private struct MockNotesAPI: NotesProviding {
    let listTreeResult: Result<FileTree, Error>

    init(listTreeResult: Result<FileTree, Error>) {
        self.listTreeResult = listTreeResult
    }

    func listTree() async throws -> FileTree {
        try listTreeResult.get()
    }

    func getNote(id: String) async throws -> NotePayload {
        _ = id
        throw MockError.forced
    }
}

private struct MockScratchpadAPI: ScratchpadProviding {
    let result: Result<ScratchpadResponse, Error>

    func get() async throws -> ScratchpadResponse {
        try result.get()
    }

    func update(content: String, mode: ScratchpadMode?) async throws -> ScratchpadResponse {
        _ = content
        _ = mode
        return try result.get()
    }
}
