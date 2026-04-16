import Foundation
import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class IngestionOfflineContentTests: XCTestCase {
    func testSelectFileUsesCachedDerivativeContentWhenServerUnreachable() async {
        let file = makeFile(id: "file-1")
        let derivative = IngestionDerivative(
            id: "d1",
            kind: "text_original",
            storageKey: "storage",
            mime: "text/plain",
            sizeBytes: 12
        )
        let meta = IngestionMetaResponse(
            file: file,
            job: makeReadyJob(),
            derivatives: [derivative],
            recommendedViewer: "text_original"
        )
        let cache = TestCacheClient()
        let defaults = makeDefaults()
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        offlineStore.set(
            key: CacheKeys.ingestionMeta(fileId: file.id),
            entityType: "file",
            value: meta,
            lastSyncAt: nil
        )
        let api = OfflineContentIngestionAPI(
            metaResult: .success(meta),
            contentResult: .failure(URLError(.cannotConnectToHost))
        )
        let store = IngestionStore(
            api: api,
            cache: cache,
            offlineStore: offlineStore,
            networkStatus: TestNetworkStatus(
                isNetworkAvailable: true,
                isOffline: false,
                isServerReachable: false
            ),
            userDefaults: defaults
        )
        store.persistDerivativeContent(Data("Hello offline".utf8), fileId: file.id, kind: derivative.kind)
        let temporaryStore = TemporaryFileStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        let viewModel = IngestionViewModel(
            api: api,
            store: store,
            temporaryStore: temporaryStore,
            uploadManager: OfflineContentUploadManager(),
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(
                isNetworkAvailable: true,
                isOffline: false,
                isServerReachable: false
            )
        )

        await viewModel.selectFile(fileId: file.id)

        XCTAssertEqual(viewModel.viewerState?.kind, .text)
        XCTAssertEqual(viewModel.viewerState?.text, "Hello offline")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(api.getContentCallCount, 0)
    }

    func testSelectFileReportsUnavailableOfflineWhenDerivativeIsNotCached() async {
        let file = makeFile(id: "file-2")
        let derivative = IngestionDerivative(
            id: "d1",
            kind: "text_original",
            storageKey: "storage",
            mime: "text/plain",
            sizeBytes: 12
        )
        let meta = IngestionMetaResponse(
            file: file,
            job: makeReadyJob(),
            derivatives: [derivative],
            recommendedViewer: "text_original"
        )
        let cache = TestCacheClient()
        let defaults = makeDefaults()
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        offlineStore.set(
            key: CacheKeys.ingestionMeta(fileId: file.id),
            entityType: "file",
            value: meta,
            lastSyncAt: nil
        )
        let api = OfflineContentIngestionAPI(
            metaResult: .success(meta),
            contentResult: .failure(URLError(.cannotConnectToHost))
        )
        let store = IngestionStore(
            api: api,
            cache: cache,
            offlineStore: offlineStore,
            networkStatus: TestNetworkStatus(
                isNetworkAvailable: true,
                isOffline: false,
                isServerReachable: false
            ),
            userDefaults: defaults
        )
        let viewModel = IngestionViewModel(
            api: api,
            store: store,
            temporaryStore: .shared,
            uploadManager: OfflineContentUploadManager(),
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(
                isNetworkAvailable: true,
                isOffline: false,
                isServerReachable: false
            )
        )

        await viewModel.selectFile(fileId: file.id)

        XCTAssertNil(viewModel.viewerState)
        XCTAssertEqual(viewModel.errorMessage, "This file isn't available offline yet.")
        XCTAssertEqual(api.getContentCallCount, 0)
    }

    func testLoadFileTransferPayloadUsesCachedDerivativeContentOffline() async throws {
        let file = makeFile(
            id: "file-3",
            filename: "file-3.pdf",
            path: "/file-3.pdf",
            mimeType: "application/pdf"
        )
        let derivative = IngestionDerivative(
            id: "d1",
            kind: "source_original",
            storageKey: "storage",
            mime: "application/pdf",
            sizeBytes: 12
        )
        let meta = IngestionMetaResponse(
            file: file,
            job: makeReadyJob(),
            derivatives: [derivative],
            recommendedViewer: "source_original"
        )
        let cache = TestCacheClient()
        let defaults = makeDefaults()
        let persistence = PersistenceController(inMemory: true)
        let offlineStore = OfflineStore(container: persistence.container)
        offlineStore.set(
            key: CacheKeys.ingestionMeta(fileId: file.id),
            entityType: "file",
            value: meta,
            lastSyncAt: nil
        )
        let api = OfflineContentIngestionAPI(
            metaResult: .success(meta),
            contentResult: .failure(URLError(.cannotConnectToHost))
        )
        let store = IngestionStore(
            api: api,
            cache: cache,
            offlineStore: offlineStore,
            networkStatus: TestNetworkStatus(
                isNetworkAvailable: true,
                isOffline: false,
                isServerReachable: false
            ),
            userDefaults: defaults
        )
        store.persistDerivativeContent(Data("pdf-bytes".utf8), fileId: file.id, kind: derivative.kind)
        let viewModel = IngestionViewModel(
            api: api,
            store: store,
            temporaryStore: .shared,
            uploadManager: OfflineContentUploadManager(),
            toastCenter: ToastCenter(),
            networkStatus: TestNetworkStatus(
                isNetworkAvailable: true,
                isOffline: false,
                isServerReachable: false
            )
        )

        let payload = try await viewModel.loadFileTransferPayload(fileId: file.id)

        XCTAssertEqual(payload.data, Data("pdf-bytes".utf8))
        XCTAssertEqual(payload.filename, "file-3.pdf")
        XCTAssertEqual(api.getContentCallCount, 0)
    }
}

private func makeFile(
    id: String,
    filename: String? = nil,
    path: String? = nil,
    mimeType: String = "text/plain"
) -> IngestedFileMeta {
    IngestedFileMeta(
        id: id,
        filenameOriginal: filename ?? "\(id).txt",
        path: path ?? "/\(id).txt",
        mimeOriginal: mimeType,
        sizeBytes: 12,
        sha256: nil,
        pinned: false,
        pinnedOrder: nil,
        category: nil,
        sourceUrl: nil,
        sourceMetadata: nil,
        createdAt: "2026-01-10T00:00:00Z",
        updatedAt: "2026-01-10T00:00:00Z",
        deletedAt: nil
    )
}

private func makeReadyJob() -> IngestionJob {
    IngestionJob(
        status: "ready",
        stage: "ready",
        errorCode: nil,
        errorMessage: nil,
        userMessage: nil,
        progress: nil,
        attempts: 0,
        updatedAt: "2026-01-10T00:00:00Z"
    )
}

private func makeDefaults() -> UserDefaults {
    let suiteName = "IngestionOfflineContentTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private struct TestNetworkStatus: NetworkStatusProviding {
    let isNetworkAvailable: Bool
    let isOffline: Bool
    let isServerReachable: Bool
}

private final class OfflineContentIngestionAPI: IngestionProviding {
    let metaResult: Result<IngestionMetaResponse, Error>
    let contentResult: Result<Data, Error>
    private(set) var getContentCallCount = 0

    init(
        metaResult: Result<IngestionMetaResponse, Error>,
        contentResult: Result<Data, Error>
    ) {
        self.metaResult = metaResult
        self.contentResult = contentResult
    }

    func list() async throws -> IngestionListResponse { IngestionListResponse(items: []) }

    func getMeta(fileId: String) async throws -> IngestionMetaResponse {
        _ = fileId
        return try metaResult.get()
    }

    func getContent(fileId: String, kind: String, range: String?) async throws -> Data {
        _ = fileId
        _ = kind
        _ = range
        getContentCallCount += 1
        return try contentResult.get()
    }

    func upload(fileURL: URL, filename: String, mimeType: String, folder: String) async throws -> String {
        _ = fileURL
        _ = filename
        _ = mimeType
        _ = folder
        throw IngestionStoreTestsSupport.MockError.forced
    }

    func cancel(fileId: String) async throws {
        _ = fileId
        throw IngestionStoreTestsSupport.MockError.forced
    }

    func pin(fileId: String, pinned: Bool, clientUpdatedAt: String?) async throws {
        _ = fileId
        _ = pinned
        _ = clientUpdatedAt
        throw IngestionStoreTestsSupport.MockError.forced
    }

    func updatePinnedOrder(ids: [String]) async throws {
        _ = ids
        throw IngestionStoreTestsSupport.MockError.forced
    }

    func delete(fileId: String, clientUpdatedAt: String?) async throws {
        _ = fileId
        _ = clientUpdatedAt
        throw IngestionStoreTestsSupport.MockError.forced
    }

    func rename(fileId: String, filename: String, clientUpdatedAt: String?) async throws {
        _ = fileId
        _ = filename
        _ = clientUpdatedAt
        throw IngestionStoreTestsSupport.MockError.forced
    }

    func ingestYouTube(url: String) async throws -> String {
        _ = url
        throw IngestionStoreTestsSupport.MockError.forced
    }

    func sync(_ payload: IngestionSyncRequest) async throws -> IngestionSyncResponse {
        _ = payload
        throw IngestionStoreTestsSupport.MockError.forced
    }
}

private final class OfflineContentUploadManager: IngestionUploadManaging {
    func startUpload(
        request: UploadRequest,
        onProgress: @escaping (Double) -> Void,
        onCompletion: @escaping (Result<String, Error>) -> Void
    ) {
        _ = request
        _ = onProgress
        _ = onCompletion
    }

    func cancelUpload(uploadId: String) {
        _ = uploadId
    }
}
