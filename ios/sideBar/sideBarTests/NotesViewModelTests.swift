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

    func search(query: String, limit: Int) async throws -> [FileNode] {
        _ = query
        _ = limit
        return []
    }
}
