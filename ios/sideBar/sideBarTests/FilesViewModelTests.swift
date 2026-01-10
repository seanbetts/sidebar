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
        let api = MockFilesAPI(
            listTreeResult: .failure(MockError.forced),
            getContentResult: .failure(MockError.forced),
            downloadResult: .failure(MockError.forced)
        )
        let viewModel = FilesViewModel(api: api, cache: cache, temporaryStore: .shared)

        await viewModel.loadTree(basePath: "documents")

        XCTAssertEqual(viewModel.tree?.children.first?.name, "Cached")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadContentCachesFreshData() async {
        let freshContent = FileContent(content: "Hello", name: "hello.txt", path: "/hello.txt", modified: nil)
        let cache = TestCacheClient()
        let api = MockFilesAPI(
            listTreeResult: .failure(MockError.forced),
            getContentResult: .success(freshContent),
            downloadResult: .failure(MockError.forced)
        )
        let viewModel = FilesViewModel(api: api, cache: cache, temporaryStore: .shared)

        await viewModel.loadContent(basePath: "documents", path: "/hello.txt")

        let cached: FileContent? = cache.get(key: CacheKeys.fileContent(basePath: "documents", path: "/hello.txt"))
        XCTAssertEqual(cached?.content, "Hello")
        XCTAssertEqual(viewModel.activeFile?.content, "Hello")
    }

    func testSelectFileBuildsMarkdownViewer() async {
        let content = FileContent(content: "# Title", name: "note.md", path: "/note.md", modified: nil)
        let cache = TestCacheClient()
        let api = MockFilesAPI(
            listTreeResult: .failure(MockError.forced),
            getContentResult: .success(content),
            downloadResult: .failure(MockError.forced)
        )
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = TemporaryFileStore(directory: tempDirectory)
        let viewModel = FilesViewModel(api: api, cache: cache, temporaryStore: store)

        await viewModel.selectFile(path: "/note.md", name: "note.md")

        XCTAssertEqual(viewModel.viewerState?.kind, .markdown)
        XCTAssertEqual(viewModel.viewerState?.text, "# Title")
        XCTAssertNotNil(viewModel.viewerState?.fileURL)
    }
}

private enum MockError: Error {
    case forced
}

private struct MockFilesAPI: FilesProviding {
    let listTreeResult: Result<FileTree, Error>
    let getContentResult: Result<FileContent, Error>
    let downloadResult: Result<Data, Error>

    func listTree(basePath: String) async throws -> FileTree {
        _ = basePath
        return try listTreeResult.get()
    }

    func getContent(basePath: String, path: String) async throws -> FileContent {
        _ = basePath
        _ = path
        return try getContentResult.get()
    }

    func download(basePath: String, path: String) async throws -> Data {
        _ = basePath
        _ = path
        return try downloadResult.get()
    }
}
