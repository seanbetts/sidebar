import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class FilesPanelPinnedReorderTests: XCTestCase {
    func testPinnedItemsReflectLocallyUpdatedPinnedOrder() async {
        let fixture = makeViewModelAndStore(
            items: [
                makeItem(id: "file-a", pinned: true, pinnedOrder: 0),
                makeItem(id: "file-b", pinned: true, pinnedOrder: 1),
                makeItem(id: "file-c", pinned: false)
            ],
            networkIsAvailable: true
        )
        let viewModel = fixture.viewModel
        let store = fixture.store
        let view = FilesPanelView(
            viewModel: viewModel,
            showsHeader: false,
            pinnedReorderNetworkAvailability: true
        )

        store.applyPinnedOrder(["file-b", "file-a"])

        XCTAssertEqual(view.pinnedItems.map(\.file.id), ["file-b", "file-a"])
    }

    func testPinnedReorderAffordancesRequireAtLeastTwoPinnedFiles() async {
        let view = makeView(
            isNetworkAvailable: true,
            items: [makeItem(id: "file-a", pinned: true, pinnedOrder: 0)]
        )

        XCTAssertFalse(view.canStartPinnedReorder)
        XCTAssertFalse(view.isPinnedReorderEditActive)
    }

    func testPinnedReorderShowsMoveHandlesWheneverPinnedSectionCanReorder() async {
        let view = makeView()

        XCTAssertTrue(view.isPinnedReorderEditActive)
    }

    func testPinnedReorderLifecycleHelpersTrackCurrentInteraction() async {
        let view = makeView()

        XCTAssertFalse(view.isPinnedReordering)

        view.enterPinnedReorder(from: "file-a")
        XCTAssertTrue(view.isPinnedReordering)
        XCTAssertEqual(view.pinnedReorderSourceID, "file-a")
        XCTAssertTrue(view.isPinnedReorderEditActive)

        view.completePinnedReorder()
        XCTAssertFalse(view.isPinnedReordering)
        XCTAssertNil(view.pinnedReorderSourceID)
        XCTAssertTrue(view.isPinnedReorderEditActive)
    }

    func testPinnedReorderRejectsOfflineActivation() async {
        let offlineView = makeView(isNetworkAvailable: false)

        XCTAssertFalse(offlineView.canStartPinnedReorder)
        XCTAssertFalse(offlineView.isPinnedReorderEditActive)
    }

    func testPinnedReorderCancelsWhenPinnedSetChangesMidGesture() async {
        let view = makeView()

        view.enterPinnedReorder(from: "file-a")
        view.handlePinnedSetChanged(["file-b"])

        XCTAssertFalse(view.isPinnedReordering)
    }

    func testPinnedReorderDropTargetsRejectNonPinnedOrCrossSectionItems() async {
        let view = makeView()

        XCTAssertFalse(
            view.canAcceptPinnedDrop(
                isPinned: false,
                sourceSection: .mainFiles,
                destinationSection: .pinned
            )
        )
        XCTAssertFalse(
            view.canAcceptPinnedDrop(
                isPinned: true,
                sourceSection: .mainFiles,
                destinationSection: .pinned
            )
        )
        XCTAssertFalse(
            view.canAcceptPinnedDrop(
                isPinned: true,
                sourceSection: .pinned,
                destinationSection: .mainFiles
            )
        )
    }

    func testPinnedReorderIndexHelperMovesPinnedFileIDs() async {
        let view = makeView()

        XCTAssertEqual(view.reorderedPinnedIDs(from: IndexSet(integer: 0), to: 2), ["file-b", "file-a"])
        XCTAssertEqual(view.reorderedPinnedIDs(moving: "file-a", to: "file-b"), ["file-a", "file-b"])
    }

    func testPinnedFileMoveKeepsSessionActiveUntilTimeoutAndPersistsFinalOrder() async {
        let (view, api) = makeViewWithAPI(autoExitDelay: 0.05)

        view.enterPinnedReorder(from: "file-a")
        view.movePinnedFiles(from: IndexSet(integer: 0), to: 2)

        XCTAssertTrue(view.isPinnedReordering)
        XCTAssertEqual(view.pinnedItems.map(\.file.id), ["file-b", "file-a"])
        XCTAssertEqual(api.updatePinnedOrderCallCount, 0)

        try? await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertFalse(view.isPinnedReordering)
        XCTAssertEqual(api.updatePinnedOrderCallCount, 1)
        XCTAssertEqual(api.lastPinnedOrderIDs, ["file-b", "file-a"])
    }

    private func makeView(
        isNetworkAvailable: Bool = true,
        items: [IngestionListItem]? = nil
    ) -> FilesPanelView {
        let (view, _) = makeViewWithAPI(
            isNetworkAvailable: isNetworkAvailable,
            items: items
        )
        return view
    }

    private func makeViewWithAPI(
        isNetworkAvailable: Bool = true,
        items: [IngestionListItem]? = nil,
        autoExitDelay: TimeInterval? = nil
    ) -> (FilesPanelView, FilesPanelTestAPI) {
        let resolvedItems = items ?? [
            makeItem(id: "file-a", pinned: true, pinnedOrder: 0),
            makeItem(id: "file-b", pinned: true, pinnedOrder: 1)
        ]
        let fixture = makeViewModelAndStore(
            items: resolvedItems,
            networkIsAvailable: isNetworkAvailable
        )
        let view = FilesPanelView(
            viewModel: fixture.viewModel,
            showsHeader: false,
            pinnedReorderNetworkAvailability: isNetworkAvailable,
            pinnedReorderAutoExitDelay: autoExitDelay
        )
        return (view, fixture.api)
    }

    private func makeViewModelAndStore(
        items: [IngestionListItem],
        networkIsAvailable: Bool
    ) -> FilesPanelTestFixture {
        let api = FilesPanelTestAPI(listResponse: IngestionListResponse(items: items))
        let defaults = UserDefaults(suiteName: "FilesPanelPinnedReorderTests.\(UUID().uuidString)")!
        let store = IngestionStore(api: api, cache: TestCacheClient(), userDefaults: defaults)
        let viewModel = IngestionViewModel(
            api: api,
            store: store,
            temporaryStore: .shared,
            uploadManager: MockFilesPanelUploadManager(),
            toastCenter: ToastCenter(),
            networkStatus: FilesPanelTestNetworkStatus(isNetworkAvailable: networkIsAvailable)
        )
        store.applyListUpdate(items, persist: false)
        return FilesPanelTestFixture(viewModel: viewModel, store: store, api: api)
    }

    private func makeItem(
        id: String,
        pinned: Bool,
        pinnedOrder: Int? = nil
    ) -> IngestionListItem {
        IngestionListItem(
            file: IngestedFileMeta(
                id: id,
                filenameOriginal: "\(id).txt",
                path: "/\(id).txt",
                mimeOriginal: "text/plain",
                sizeBytes: 12,
                sha256: nil,
                pinned: pinned,
                pinnedOrder: pinnedOrder,
                category: "documents",
                sourceUrl: nil,
                sourceMetadata: nil,
                createdAt: "2026-03-22T10:00:00Z",
                updatedAt: "2026-03-22T10:00:00Z",
                deletedAt: nil
            ),
            job: IngestionJob(
                status: "ready",
                stage: "ready",
                errorCode: nil,
                errorMessage: nil,
                userMessage: nil,
                progress: nil,
                attempts: 0,
                updatedAt: "2026-03-22T10:00:00Z"
            ),
            recommendedViewer: "text_original"
        )
    }
}

private struct FilesPanelTestFixture {
    let viewModel: IngestionViewModel
    let store: IngestionStore
    let api: FilesPanelTestAPI
}

private struct FilesPanelTestNetworkStatus: NetworkStatusProviding {
    let isNetworkAvailable: Bool
    let isOffline: Bool = false
}

private final class FilesPanelTestAPI: IngestionProviding {
    let listResponse: IngestionListResponse
    private(set) var updatePinnedOrderCallCount = 0
    private(set) var lastPinnedOrderIDs: [String] = []

    init(listResponse: IngestionListResponse) {
        self.listResponse = listResponse
    }

    func list() async throws -> IngestionListResponse {
        listResponse
    }

    func getMeta(fileId: String) async throws -> IngestionMetaResponse {
        _ = fileId
        throw FilesPanelTestError.unused
    }

    func getContent(fileId: String, kind: String, range: String?) async throws -> Data {
        _ = fileId
        _ = kind
        _ = range
        throw FilesPanelTestError.unused
    }

    func upload(fileURL: URL, filename: String, mimeType: String, folder: String) async throws -> String {
        _ = fileURL
        _ = filename
        _ = mimeType
        _ = folder
        throw FilesPanelTestError.unused
    }

    func cancel(fileId: String) async throws {
        _ = fileId
        throw FilesPanelTestError.unused
    }

    func pin(fileId: String, pinned: Bool, clientUpdatedAt: String?) async throws {
        _ = fileId
        _ = pinned
        _ = clientUpdatedAt
        throw FilesPanelTestError.unused
    }

    func updatePinnedOrder(ids: [String]) async throws {
        updatePinnedOrderCallCount += 1
        lastPinnedOrderIDs = ids
    }

    func delete(fileId: String, clientUpdatedAt: String?) async throws {
        _ = fileId
        _ = clientUpdatedAt
        throw FilesPanelTestError.unused
    }

    func rename(fileId: String, filename: String, clientUpdatedAt: String?) async throws {
        _ = fileId
        _ = filename
        _ = clientUpdatedAt
        throw FilesPanelTestError.unused
    }

    func ingestYouTube(url: String) async throws -> String {
        _ = url
        throw FilesPanelTestError.unused
    }

    func sync(_ payload: IngestionSyncRequest) async throws -> IngestionSyncResponse {
        _ = payload
        throw FilesPanelTestError.unused
    }
}

private enum FilesPanelTestError: Error {
    case unused
}

private final class MockFilesPanelUploadManager: IngestionUploadManaging {
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
