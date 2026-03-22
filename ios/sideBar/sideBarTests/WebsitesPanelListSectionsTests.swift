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
        let (viewModel, store) = makeViewModelAndStore(
            items: [
                makeWebsiteItem(id: "w1", pinned: true, pinnedOrder: 0),
                makeWebsiteItem(id: "w2", pinned: true, pinnedOrder: 1),
                makeWebsiteItem(id: "w3", pinned: false, pinnedOrder: nil)
            ],
            networkIsAvailable: true
        )
        await viewModel.load()
        let panel = WebsitesPanelView(
            viewModel: viewModel,
            pinnedReorderNetworkAvailability: true
        )

        store.applyPinnedOrder(["w2", "w1"])

        XCTAssertEqual(panel.pinnedItemsSorted.map(\.id), ["w2", "w1"])
    }

    func testPinnedReorderAffordancesRequireAtLeastTwoPinnedSites() async {
        let panel = await makeView(
            isNetworkAvailable: true,
            items: [makeWebsiteItem(id: "w1", pinned: true, pinnedOrder: 0)]
        )

        XCTAssertFalse(panel.canStartPinnedReorder)
    }

    func testPinnedReorderLifecycleHelpersTrackCurrentInteraction() async {
        let view = await makeView()

        XCTAssertEqual(view.pinnedReorderEditMode, .inactive)

        view.enterPinnedReorder(from: "w1")
        XCTAssertTrue(view.isPinnedReordering)
        XCTAssertEqual(view.pinnedReorderSourceID, "w1")
        XCTAssertEqual(view.pinnedReorderEditMode, .active)

        view.completePinnedReorder()
        XCTAssertFalse(view.isPinnedReordering)
        XCTAssertNil(view.pinnedReorderSourceID)
        XCTAssertEqual(view.pinnedReorderEditMode, .inactive)
    }

    func testPinnedReorderRejectsOfflineActivation() async {
        let offlineView = await makeView(isNetworkAvailable: false)

        XCTAssertFalse(offlineView.canStartPinnedReorder)
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

    func testPinnedWebsiteContextMenuIncludesReorderWhenPinnedSectionCanReorder() async {
        let view = await makeView()
        let item = view.pinnedItemsSorted[0]

        let titles = view.websiteContextMenuItemsList(for: item).map(\.title)

        XCTAssertTrue(titles.contains("Reorder"))
    }

    func testPinnedWebsiteContextMenuHidesReorderWhenPinnedSectionCannotReorder() async {
        let view = await makeView(isNetworkAvailable: false)
        let item = view.pinnedItemsSorted[0]

        let titles = view.websiteContextMenuItemsList(for: item).map(\.title)

        XCTAssertFalse(titles.contains("Reorder"))
    }

    func testSwipeActionArchivesReturnsFalseForArchivedItem() {
        let item = makeWebsiteItem(archived: true)

        let result = WebsitesPanelView.swipeActionArchives(item: item, allowArchive: true)

        XCTAssertFalse(result)
    }

    func testSwipeActionArchivesReturnsTrueForActiveItemWhenAllowed() {
        let item = makeWebsiteItem(archived: false)

        let result = WebsitesPanelView.swipeActionArchives(item: item, allowArchive: true)

        XCTAssertTrue(result)
    }

    func testSwipeActionArchivesRespectsExplicitDisallow() {
        let item = makeWebsiteItem(archived: false)

        let result = WebsitesPanelView.swipeActionArchives(item: item, allowArchive: false)

        XCTAssertFalse(result)
    }

    private func makeView(
        isNetworkAvailable: Bool = true,
        items: [WebsiteItem]? = nil
    ) async -> WebsitesPanelView {
        let resolvedItems = items ?? [
            makeWebsiteItem(id: "w1", pinned: true, pinnedOrder: 0),
            makeWebsiteItem(id: "w2", pinned: true, pinnedOrder: 1)
        ]
        let (viewModel, _) = makeViewModelAndStore(items: resolvedItems, networkIsAvailable: isNetworkAvailable)
        await viewModel.load()
        return WebsitesPanelView(
            viewModel: viewModel,
            pinnedReorderNetworkAvailability: isNetworkAvailable
        )
    }

    private func makeViewModelAndStore(
        items: [WebsiteItem],
        networkIsAvailable: Bool
    ) -> (viewModel: WebsitesViewModel, store: WebsitesStore) {
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
        return (viewModel, store)
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

private struct WebsitesPanelTestNetworkStatus: NetworkStatusProviding {
    let isNetworkAvailable: Bool
    let isOffline: Bool = false
}

private final class WebsitesPanelTestWebsitesAPI: WebsitesProviding {
    let listResponse: WebsitesResponse
    let archivedListResponse: WebsitesResponse

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
        _ = ids
        throw WebsitesPanelTestError.unused
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
