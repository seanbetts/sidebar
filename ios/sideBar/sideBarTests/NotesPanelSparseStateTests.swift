import XCTest
@testable import sideBar

@MainActor
final class NotesPanelSparseStateTests: XCTestCase {
    func testPanelStatePrefersLoadingBeforeSparseState() {
        XCTAssertEqual(
            NotesPanelView.resolvePanelState(
                isTreeLoaded: false,
                hasError: false,
                searchQuery: "",
                pinnedCount: 0,
                mainNodeCount: 0
            ),
            .loading
        )
    }

    func testPanelStateUsesSearchWhenQueryIsPresent() {
        XCTAssertEqual(
            NotesPanelView.resolvePanelState(
                isTreeLoaded: true,
                hasError: false,
                searchQuery: "docs",
                pinnedCount: 0,
                mainNodeCount: 0
            ),
            .search
        )
    }

    func testPanelStateUsesSparseWhenPinnedAndMainNodesAreEmpty() {
        XCTAssertEqual(
            NotesPanelView.resolvePanelState(
                isTreeLoaded: true,
                hasError: false,
                searchQuery: "",
                pinnedCount: 0,
                mainNodeCount: 0
            ),
            .sparse
        )
    }

    func testPanelStateDoesNotUseSparseBeforeSuccessfulTreeLoad() {
        XCTAssertEqual(
            NotesPanelView.resolvePanelState(
                isTreeLoaded: true,
                hasError: false,
                searchQuery: "",
                pinnedCount: 0,
                mainNodeCount: 0,
                treeLoadState: .idle
            ),
            .loading
        )
    }

    func testPanelStateUsesErrorForFailedEmptyTreeLoad() {
        XCTAssertEqual(
            NotesPanelView.resolvePanelState(
                isTreeLoaded: true,
                hasError: true,
                searchQuery: "",
                pinnedCount: 0,
                mainNodeCount: 0,
                treeLoadState: .failed("Session expired")
            ),
            .error
        )
    }

    func testPanelStateReturnsErrorWhenTreeIsUnavailableAndErrorExists() {
        XCTAssertEqual(
            NotesPanelView.resolvePanelState(
                isTreeLoaded: false,
                hasError: true,
                searchQuery: "",
                pinnedCount: 0,
                mainNodeCount: 0
            ),
            .error
        )
    }

    func testPanelStateReturnsContentWhenPrimaryContentExists() {
        XCTAssertEqual(
            NotesPanelView.resolvePanelState(
                isTreeLoaded: true,
                hasError: false,
                searchQuery: "",
                pinnedCount: 0,
                mainNodeCount: 1
            ),
            .content
        )
    }

    func testSparseStateCopyMatchesNotesSection() {
        XCTAssertEqual(NotesPanelView.sparseStateTitle, "No notes yet")
        XCTAssertNil(NotesPanelView.sparseStateSubtitle)
    }
}
