import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class WebsitesPanelListSectionsTests: XCTestCase {
    func testSectionOrderShowsSparseStateThenArchiveWhenOnlyArchiveRemains() {
        XCTAssertEqual(
            WebsitesPanelView.listSectionLayout(
                panelState: .sparse,
                hasPinnedItems: false,
                hasMainItems: false,
                hasPendingItems: false
            ),
            [.sparseState, .archive]
        )
    }

    func testSectionOrderShowsPrimaryContentThenArchiveWhenItemsExist() {
        XCTAssertEqual(
            WebsitesPanelView.listSectionLayout(
                panelState: .content,
                hasPinnedItems: true,
                hasMainItems: false,
                hasPendingItems: false
            ),
            [.primaryContent, .archive]
        )
    }

    func testPinnedItemsReflectLocallyUpdatedPinnedOrder() async {
        let fixture = makeViewModelAndStore(
            items: [
                makeWebsiteItem(id: "w1", pinned: true, pinnedOrder: 0),
                makeWebsiteItem(id: "w2", pinned: true, pinnedOrder: 1),
                makeWebsiteItem(id: "w3", pinned: false, pinnedOrder: nil)
            ],
            networkIsAvailable: true
        )
        let viewModel = fixture.viewModel
        let store = fixture.store
        await viewModel.load()
        let panel = WebsitesPanelView(
            viewModel: viewModel,
            pinnedReorderNetworkAvailability: true
        )

        store.applyPinnedOrder(["w2", "w1"])

        XCTAssertEqual(panel.pinnedItemsSorted.map { $0.id }, ["w2", "w1"])
    }

    func testPinnedReorderAffordancesRequireAtLeastTwoPinnedSites() async {
        let panel = await makeView(
            isNetworkAvailable: true,
            items: [makeWebsiteItem(id: "w1", pinned: true, pinnedOrder: 0)]
        )

        XCTAssertFalse(panel.canStartPinnedReorder)
        XCTAssertFalse(panel.isPinnedReorderEditActive)
    }

    func testPinnedReorderShowsMoveHandlesWheneverPinnedSectionCanReorder() async {
        let view = await makeView()

        XCTAssertTrue(view.isPinnedReorderEditActive)
    }

    func testPinnedReorderLifecycleHelpersTrackCurrentInteraction() async {
        let view = await makeView()

        XCTAssertFalse(view.isPinnedReordering)

        view.enterPinnedReorder(from: "w1")
        XCTAssertTrue(view.isPinnedReordering)
        XCTAssertEqual(view.pinnedReorderSourceID, "w1")
        XCTAssertTrue(view.isPinnedReorderEditActive)

        view.completePinnedReorder()
        XCTAssertFalse(view.isPinnedReordering)
        XCTAssertNil(view.pinnedReorderSourceID)
        XCTAssertTrue(view.isPinnedReorderEditActive)
    }

    func testPinnedReorderRejectsOfflineActivation() async {
        let offlineView = await makeView(isNetworkAvailable: false)

        XCTAssertFalse(offlineView.canStartPinnedReorder)
        XCTAssertFalse(offlineView.isPinnedReorderEditActive)
    }

    func testPinnedReorderMoveKeepsSessionActiveUntilTimeoutAndPersistsFinalOrder() async {
        let (view, api) = await makeViewWithAPI(autoExitDelay: 0.05)

        view.enterPinnedReorder(from: "w1")
        view.movePinnedWebsites(from: IndexSet(integer: 0), to: 2)

        XCTAssertTrue(view.isPinnedReordering)
        XCTAssertEqual(view.pinnedItemsSorted.map { $0.id }, ["w2", "w1"])
        XCTAssertEqual(api.updatePinnedOrderCallCount, 0)

        try? await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertFalse(view.isPinnedReordering)
        XCTAssertEqual(api.updatePinnedOrderCallCount, 1)
        XCTAssertEqual(api.lastPinnedOrderIDs, ["w2", "w1"])
    }

    func testPinnedReorderCancelsWhenPinnedSetChangesMidGesture() async {
        let view = await makeView()

        view.enterPinnedReorder(from: "w1")
        view.handlePinnedSetChanged(["w2"])

        XCTAssertFalse(view.isPinnedReordering)
    }

    func testPinnedReorderDropTargetsRejectNonPinnedOrCrossSectionItems() async {
        let view = await makeView()

        XCTAssertFalse(
            view.canAcceptPinnedDrop(
                isPinned: false,
                sourceSection: .mainWebsites,
                destinationSection: .pinned
            )
        )
        XCTAssertFalse(
            view.canAcceptPinnedDrop(
                isPinned: true,
                sourceSection: .mainWebsites,
                destinationSection: .pinned
            )
        )
        XCTAssertFalse(
            view.canAcceptPinnedDrop(
                isPinned: true,
                sourceSection: .pinned,
                destinationSection: .mainWebsites
            )
        )
    }

    func testPinnedReorderIndexHelperMovesPinnedWebsiteIDs() async {
        let view = await makeView()

        XCTAssertEqual(view.reorderedPinnedIDs(from: IndexSet(integer: 0), to: 2), ["w2", "w1"])
        XCTAssertEqual(view.reorderedPinnedIDs(moving: "w1", to: "w2"), ["w1", "w2"])
    }

    func testPinnedWebsiteContextMenuDoesNotIncludeReorderWhenHandlesAreAlwaysVisible() async {
        let view = await makeView()
        let item = view.pinnedItemsSorted[0]

        let titles = view.websiteContextMenuItemsList(for: item).map(\.title)

        XCTAssertFalse(titles.contains("Reorder"))
    }

    private func makeView(
        isNetworkAvailable: Bool = true,
        items: [WebsiteItem]? = nil
    ) async -> WebsitesPanelView {
        let (view, _) = await makeViewWithAPI(
            isNetworkAvailable: isNetworkAvailable,
            items: items
        )
        return view
    }

    private func makeViewWithAPI(
        isNetworkAvailable: Bool = true,
        items: [WebsiteItem]? = nil,
        autoExitDelay: TimeInterval? = nil
    ) async -> (WebsitesPanelView, WebsitesPanelTestWebsitesAPI) {
        let resolvedItems = items ?? [
            makeWebsiteItem(id: "w1", pinned: true, pinnedOrder: 0),
            makeWebsiteItem(id: "w2", pinned: true, pinnedOrder: 1)
        ]
        let fixture = makeViewModelAndStore(
            items: resolvedItems,
            networkIsAvailable: isNetworkAvailable
        )
        let viewModel = fixture.viewModel
        let api = fixture.api
        await viewModel.load()
        let view = WebsitesPanelView(
            viewModel: viewModel,
            pinnedReorderNetworkAvailability: isNetworkAvailable,
            pinnedReorderAutoExitDelay: autoExitDelay
        )
        return (view, api)
    }

    private func makeViewModelAndStore(
        items: [WebsiteItem],
        networkIsAvailable: Bool
    ) -> WebsitesPanelTestFixture {
        let api = WebsitesPanelTestWebsitesAPI(
            listResponse: WebsitesResponse(items: items),
            archivedListResponse: WebsitesResponse(items: [])
        )
        let store = WebsitesStore(api: api, cache: InMemoryCacheClient())
        let viewModel = WebsitesViewModel(
            api: api,
            store: store,
            toastCenter: ToastCenter(),
            networkStatus: WebsitesPanelTestNetworkStatus(isNetworkAvailable: networkIsAvailable)
        )
        items.forEach { store.updateListItem($0, persist: false) }
        return WebsitesPanelTestFixture(viewModel: viewModel, store: store, api: api)
    }

    private func makeWebsiteItem(
        id: String = "site-1",
        pinned: Bool = false,
        pinnedOrder: Int? = nil,
        archived: Bool = false
    ) -> WebsiteItem {
        WebsiteItem(
            id: id,
            title: "Site",
            url: "https://example.com/\(id)",
            domain: "example.com",
            savedAt: nil,
            publishedAt: nil,
            pinned: pinned,
            pinnedOrder: pinnedOrder,
            archived: archived,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: nil,
            readingTime: nil,
            updatedAt: "2026-03-21T10:00:00Z",
            lastOpenedAt: nil,
            deletedAt: nil
        )
    }
}

private struct WebsitesPanelTestFixture {
    let viewModel: WebsitesViewModel
    let store: WebsitesStore
    let api: WebsitesPanelTestWebsitesAPI
}

private struct WebsitesPanelTestNetworkStatus: NetworkStatusProviding {
    let isNetworkAvailable: Bool
    let isOffline: Bool = false
}

private final class WebsitesPanelTestWebsitesAPI: WebsitesProviding {
    let listResponse: WebsitesResponse
    let archivedListResponse: WebsitesResponse
    private(set) var updatePinnedOrderCallCount = 0
    private(set) var lastPinnedOrderIDs: [String] = []

    init(listResponse: WebsitesResponse, archivedListResponse: WebsitesResponse) {
        self.listResponse = listResponse
        self.archivedListResponse = archivedListResponse
    }

    func list() async throws -> WebsitesResponse {
        return listResponse
    }

    func listArchived(limit: Int, offset: Int) async throws -> WebsitesResponse {
        _ = limit
        _ = offset
        return archivedListResponse
    }

    func get(id: String) async throws -> WebsiteDetail {
        _ = id
        throw WebsitesPanelTestError.unused
    }

    func save(url: String) async throws -> WebsiteSaveJobResponse {
        _ = url
        throw WebsitesPanelTestError.unused
    }

    func jobStatus(id: String) async throws -> WebsiteJobStatusResponse {
        _ = id
        throw WebsitesPanelTestError.unused
    }

    func cancel(jobId: String) async throws {
        _ = jobId
        throw WebsitesPanelTestError.unused
    }

    func transcribeYouTube(id: String, url: String) async throws -> WebsiteTranscriptResponse {
        _ = id
        _ = url
        throw WebsitesPanelTestError.unused
    }

    func pin(id: String, pinned: Bool, clientUpdatedAt: String?) async throws -> WebsiteItem {
        _ = id
        _ = pinned
        _ = clientUpdatedAt
        throw WebsitesPanelTestError.unused
    }

    func rename(id: String, title: String, clientUpdatedAt: String?) async throws -> WebsiteItem {
        _ = id
        _ = title
        _ = clientUpdatedAt
        throw WebsitesPanelTestError.unused
    }

    func archive(id: String, archived: Bool, clientUpdatedAt: String?) async throws -> WebsiteItem {
        _ = id
        _ = archived
        _ = clientUpdatedAt
        throw WebsitesPanelTestError.unused
    }

    func updatePinnedOrder(ids: [String]) async throws {
        updatePinnedOrderCallCount += 1
        lastPinnedOrderIDs = ids
    }

    func delete(id: String, clientUpdatedAt: String?) async throws {
        _ = id
        _ = clientUpdatedAt
        throw WebsitesPanelTestError.unused
    }

    func sync(_ payload: WebsiteSyncRequest) async throws -> WebsiteSyncResponse {
        _ = payload
        throw WebsitesPanelTestError.unused
    }
}

private enum WebsitesPanelTestError: Error {
    case unused
}
