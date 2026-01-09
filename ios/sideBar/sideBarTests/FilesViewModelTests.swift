import XCTest
@testable import sideBar

@MainActor
final class FilesViewModelTests: XCTestCase {
    func testLoadTreeUsesCacheOnFailure() async {
        let cachedTree = FileTree(children: [
            FileNode(
                name: "Cached",
                path: "/cached.md",
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
        let cache = TestCacheClient()
        cache.set(key: CacheKeys.filesTree(basePath: "documents"), value: cachedTree, ttlSeconds: 60)
        let api = MockFilesAPI(listTreeResult: .failure(MockError.forced), getContentResult: .failure(MockError.forced))
        let viewModel = FilesViewModel(api: api, cache: cache)

        await viewModel.loadTree(basePath: "documents")

        XCTAssertEqual(viewModel.tree?.children.first?.name, "Cached")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadContentCachesFreshData() async {
        let freshContent = FileContent(content: "Hello", name: "hello.txt", path: "/hello.txt", modified: nil)
        let cache = TestCacheClient()
        let api = MockFilesAPI(listTreeResult: .failure(MockError.forced), getContentResult: .success(freshContent))
        let viewModel = FilesViewModel(api: api, cache: cache)

        await viewModel.loadContent(basePath: "documents", path: "/hello.txt")

        let cached: FileContent? = cache.get(key: CacheKeys.fileContent(basePath: "documents", path: "/hello.txt"))
        XCTAssertEqual(cached?.content, "Hello")
        XCTAssertEqual(viewModel.activeFile?.content, "Hello")
    }
}

private enum MockError: Error {
    case forced
}

private struct MockFilesAPI: FilesProviding {
    let listTreeResult: Result<FileTree, Error>
    let getContentResult: Result<FileContent, Error>

    func listTree(basePath: String) async throws -> FileTree {
        _ = basePath
        return try listTreeResult.get()
    }

    func getContent(basePath: String, path: String) async throws -> FileContent {
        _ = basePath
        _ = path
        return try getContentResult.get()
    }
}
