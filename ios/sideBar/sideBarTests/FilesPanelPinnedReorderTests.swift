import sideBarShared
import SwiftUI
import XCTest
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

    func testFileSelectionBindingDefersPublishedSelectionMutationUntilAsyncOpenTask() async {
        let fixture = makeViewModelAndStore(
            items: [makeItem(id: "file-a", pinned: false)],
            networkIsAvailable: true
        )
        let viewModel = fixture.viewModel
        let view = FilesPanelView(
            viewModel: viewModel,
            showsHeader: false,
            pinnedReorderNetworkAvailability: true
        )

        XCTAssertNil(viewModel.selectedFileId)

        view.open(fileId: "file-a")

        XCTAssertNil(viewModel.selectedFileId)

        let deadline = DispatchTime.now().uptimeNanoseconds + 1_000_000_000
        while viewModel.selectedFileId != "file-a",
              DispatchTime.now().uptimeNanoseconds < deadline {
            await Task.yield()
        }

        XCTAssertEqual(viewModel.selectedFileId, "file-a")
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

    func testPinnedFileMovePersistsFinalOrderUsingPlatformInteractionModel() async {
        let (view, api) = makeViewWithAPI(autoExitDelay: 0.05)

        #if !os(iOS)
        view.enterPinnedReorder(from: "file-a")
        #endif
        view.movePinnedFiles(from: IndexSet(integer: 0), to: 2)

        #if os(iOS)
        let deadline = DispatchTime.now().uptimeNanoseconds + 1_000_000_000
        while api.updatePinnedOrderCallCount != 1,
              DispatchTime.now().uptimeNanoseconds < deadline {
            await Task.yield()
        }

        XCTAssertEqual(api.updatePinnedOrderCallCount, 1)
        XCTAssertEqual(api.lastPinnedOrderIDs, ["file-b", "file-a"])
        XCTAssertEqual(view.pinnedItems.map(\.file.id), ["file-b", "file-a"])
        #else
        XCTAssertTrue(view.isPinnedReordering)
        XCTAssertEqual(view.pinnedItems.map(\.file.id), ["file-b", "file-a"])
        XCTAssertEqual(api.updatePinnedOrderCallCount, 0)

        let deadline = DispatchTime.now().uptimeNanoseconds + 1_000_000_000
        while view.isPinnedReordering,
              DispatchTime.now().uptimeNanoseconds < deadline {
            await Task.yield()
        }

        XCTAssertFalse(view.isPinnedReordering)
        XCTAssertEqual(api.updatePinnedOrderCallCount, 1)
        XCTAssertEqual(api.lastPinnedOrderIDs, ["file-b", "file-a"])
        #endif
    }

    func testFileRowPrimaryActionExistsForSelectableRows() {
        let view = makeView(
            items: [makeItem(id: "file-a", pinned: false)]
        )

        XCTAssertNotNil(view.fileRowPrimaryAction(for: makeItem(id: "file-a", pinned: false)))
    }

    func testFileRowPrimaryActionReturnsNilForFolders() {
        let view = makeView(
            items: [makeItem(id: "folder-a", pinned: false, category: "folder")]
        )

        XCTAssertNil(view.fileRowPrimaryAction(for: makeItem(id: "folder-a", pinned: false, category: "folder")))
    }

    func testToggleCategoryExpansionAddsAndRemovesExpandedState() {
        let expanded = FilesPanelView.toggledExpandedCategories([], category: "documents")
        let collapsed = FilesPanelView.toggledExpandedCategories(expanded, category: "documents")

        XCTAssertEqual(expanded, ["documents"])
        XCTAssertEqual(collapsed, [])
    }

    func testFilesPanelSourceUsesHoverableSelectableCategoryRows() throws {
        let normalized = try filesPanelSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("SelectableRow("))
        XCTAssertTrue(normalized.contains("toggleCategoryExpansion(category)"))
        XCTAssertTrue(normalized.contains("chevron.down"))
        XCTAssertTrue(normalized.contains("chevron.right"))
        XCTAssertFalse(normalized.contains("DisclosureGroup("))
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
        pinnedOrder: Int? = nil,
        category: String = "documents"
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
                category: category,
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

private func filesPanelSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sourceURL = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("sideBar")
        .appendingPathComponent("Views")
        .appendingPathComponent("SidebarPanels")
        .appendingPathComponent("FilesPanel.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read FilesPanel.swift: \(error)", file: file, line: line)
        throw error
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
