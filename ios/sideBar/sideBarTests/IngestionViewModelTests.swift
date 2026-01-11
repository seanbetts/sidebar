import XCTest
@testable import sideBar

@MainActor
final class IngestionViewModelTests: XCTestCase {
    func testLoadUsesCacheOnFailure() async {
        let cachedItem = makeListItem(id: "cached")
        let cache = TestCacheClient()
        cache.set(
            key: CacheKeys.ingestionList,
            value: IngestionListResponse(items: [cachedItem]),
            ttlSeconds: 60
        )
        let api = MockIngestionAPI(
            listResult: .failure(MockError.forced),
            metaResult: .failure(MockError.forced),
            contentResult: .failure(MockError.forced),
            pinResult: .failure(MockError.forced)
        )
        let store = IngestionStore(api: api, cache: cache)
        let viewModel = IngestionViewModel(api: api, store: store, temporaryStore: .shared)

        await viewModel.load()

        XCTAssertEqual(viewModel.items.first?.file.id, "cached")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testSelectFileLoadsViewerState() async {
        let file = makeFile(id: "file-1")
        let meta = IngestionMetaResponse(
            file: file,
            job: makeJob(),
            derivatives: [
                IngestionDerivative(
                    id: "d1",
                    kind: "text_original",
                    storageKey: "storage",
                    mime: "text/plain",
                    sizeBytes: 10
                )
            ],
            recommendedViewer: "text_original"
        )
        let api = MockIngestionAPI(
            listResult: .success(IngestionListResponse(items: [makeListItem(id: file.id)])),
            metaResult: .success(meta),
            contentResult: .success(Data("Hello".utf8)),
            pinResult: .success(())
        )
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = TemporaryFileStore(directory: tempDirectory)
        let ingestionStore = IngestionStore(api: api, cache: TestCacheClient())
        let viewModel = IngestionViewModel(api: api, store: ingestionStore, temporaryStore: store)

        await viewModel.selectFile(fileId: file.id)

        XCTAssertEqual(viewModel.viewerState?.kind, .text)
        XCTAssertEqual(viewModel.viewerState?.text, "Hello")
        XCTAssertNotNil(viewModel.viewerState?.fileURL)
    }

    private func makeListItem(id: String) -> IngestionListItem {
        IngestionListItem(
            file: makeFile(id: id),
            job: makeJob(),
            recommendedViewer: "text_original"
        )
    }

    private func makeFile(id: String) -> IngestedFileMeta {
        IngestedFileMeta(
            id: id,
            filenameOriginal: "file.txt",
            path: nil,
            mimeOriginal: "text/plain",
            sizeBytes: 10,
            sha256: nil,
            pinned: false,
            pinnedOrder: nil,
            category: nil,
            sourceUrl: nil,
            sourceMetadata: nil,
            createdAt: "2026-01-10T00:00:00Z"
        )
    }

    private func makeJob() -> IngestionJob {
        IngestionJob(
            status: "ready",
            stage: "done",
            errorCode: nil,
            errorMessage: nil,
            userMessage: nil,
            progress: nil,
            attempts: 1,
            updatedAt: nil
        )
    }
}

private enum MockError: Error {
    case forced
}

private struct MockIngestionAPI: IngestionProviding {
    let listResult: Result<IngestionListResponse, Error>
    let metaResult: Result<IngestionMetaResponse, Error>
    let contentResult: Result<Data, Error>
    let pinResult: Result<Void, Error>

    func list() async throws -> IngestionListResponse {
        try listResult.get()
    }

    func getMeta(fileId: String) async throws -> IngestionMetaResponse {
        _ = fileId
        return try metaResult.get()
    }

    func getContent(fileId: String, kind: String, range: String?) async throws -> Data {
        _ = fileId
        _ = kind
        _ = range
        return try contentResult.get()
    }

    func pin(fileId: String, pinned: Bool) async throws {
        _ = fileId
        _ = pinned
        return try pinResult.get()
    }
}
