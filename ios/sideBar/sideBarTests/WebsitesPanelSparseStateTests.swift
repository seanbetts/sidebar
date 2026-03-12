import XCTest
@testable import sideBar

final class WebsitesPanelSparseStateTests: XCTestCase {
    func testPanelStatePrefersLoadingBeforeSparseState() {
        XCTAssertEqual(
            WebsitesPanelView.resolvePanelState(
                isLoading: true,
                hasError: false,
                hasLoadedContent: false,
                panelSearchQuery: "",
                pinnedCount: 0,
                mainCount: 0,
                pendingCount: 0
            ),
            .loading
        )
    }

    func testPanelStateUsesSearchWhenQueryIsPresent() {
        XCTAssertEqual(
            WebsitesPanelView.resolvePanelState(
                isLoading: false,
                hasError: false,
                hasLoadedContent: false,
                panelSearchQuery: "example",
                pinnedCount: 0,
                mainCount: 0,
                pendingCount: 0
            ),
            .search
        )
    }

    func testPanelStateUsesSparseWhenOnlyArchiveRemains() {
        XCTAssertEqual(
            WebsitesPanelView.resolvePanelState(
                isLoading: false,
                hasError: false,
                hasLoadedContent: true,
                panelSearchQuery: "",
                pinnedCount: 0,
                mainCount: 0,
                pendingCount: 0
            ),
            .sparse
        )
    }

    func testPanelStateUsesContentWhenPendingItemsExist() {
        XCTAssertEqual(
            WebsitesPanelView.resolvePanelState(
                isLoading: false,
                hasError: false,
                hasLoadedContent: false,
                panelSearchQuery: "",
                pinnedCount: 0,
                mainCount: 0,
                pendingCount: 1
            ),
            .content
        )
    }

    func testPanelStateDoesNotReturnLoadingWhenLocalContentExists() {
        XCTAssertEqual(
            WebsitesPanelView.resolvePanelState(
                isLoading: true,
                hasError: false,
                hasLoadedContent: true,
                panelSearchQuery: "",
                pinnedCount: 1,
                mainCount: 0,
                pendingCount: 0
            ),
            .content
        )
    }

    func testSparseStateCopyMatchesWebsitesSection() {
        XCTAssertEqual(WebsitesPanelView.sparseStateTitle, "No websites yet")
        XCTAssertEqual(
            WebsitesPanelView.sparseStateSubtitle,
            "Archived websites are still available below."
        )
    }
}
