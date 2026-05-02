import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class LoadableStateTests: XCTestCase {
    func testLoadingStateComputedProperties() async {
        let idle: LoadingState<String> = .idle
        XCTAssertFalse(idle.isLoading)
        XCTAssertNil(idle.value)
        XCTAssertNil(idle.error)

        let loading: LoadingState<String> = .loading
        XCTAssertTrue(loading.isLoading)

        let loaded: LoadingState<String> = .loaded("value")
        XCTAssertEqual(loaded.value, "value")
        XCTAssertNil(loaded.error)

        let failed: LoadingState<String> = .failed("oops")
        XCTAssertEqual(failed.error, "oops")
        XCTAssertNil(failed.value)
    }

    func testLoadableViewModelWithLoadingSuccess() async {
        let viewModel = TestLoadableViewModel()

        await viewModel.withLoading({
            "done"
        }, onSuccess: { value in
            viewModel.lastValue = value
        })

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.lastValue, "done")
    }

    func testLoadableViewModelWithLoadingFailure() async {
        let viewModel = TestLoadableViewModel()

        await viewModel.withLoading({
            throw URLError(.notConnectedToInternet)
        })

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.errorMessage, "Network connection failed. Please check your internet.")
    }

    func testContentListLoadStateRequiresSuccessfulLoadBeforeEmptyState() {
        let idle = ContentListLoadState.idle
        XCTAssertFalse(idle.canShowEmptyState)
        XCTAssertFalse(idle.isLoading)
        XCTAssertNil(idle.errorMessage)

        let loading = ContentListLoadState.loading
        XCTAssertFalse(loading.canShowEmptyState)
        XCTAssertTrue(loading.isLoading)

        let failed = ContentListLoadState.failed("Session expired. Please sign in again.")
        XCTAssertFalse(failed.canShowEmptyState)
        XCTAssertFalse(failed.isLoading)
        XCTAssertEqual(failed.errorMessage, "Session expired. Please sign in again.")

        let loaded = ContentListLoadState.loaded
        XCTAssertTrue(loaded.canShowEmptyState)
        XCTAssertFalse(loaded.isLoading)
        XCTAssertNil(loaded.errorMessage)
    }

    func testContentListLoadStateTrimsBlankFailureMessages() {
        XCTAssertEqual(ContentListLoadState.failure(message: " Session expired ").errorMessage, "Session expired")
        XCTAssertEqual(ContentListLoadState.failure(message: "   ").errorMessage, "Unable to load content")
    }

    func testContentListPresentationStateRequiresLoadedStateBeforeEmptyState() {
        XCTAssertEqual(
            ContentListPresentationState.resolve(
                loadState: .idle,
                isLoading: false,
                errorMessage: nil,
                searchQuery: "",
                hasLoadedContent: false,
                contentCount: 0
            ),
            .loading
        )
        XCTAssertEqual(
            ContentListPresentationState.resolve(
                loadState: .loaded,
                isLoading: false,
                errorMessage: nil,
                searchQuery: "",
                hasLoadedContent: false,
                contentCount: 0
            ),
            .empty
        )
    }

    func testContentListPresentationStatePrefersRetryForEmptyFailedLoads() {
        XCTAssertEqual(
            ContentListPresentationState.resolve(
                loadState: .failed("Session expired. Please sign in again."),
                isLoading: false,
                errorMessage: "Session expired. Please sign in again.",
                searchQuery: "",
                hasLoadedContent: false,
                contentCount: 0
            ),
            .retry(message: "Session expired. Please sign in again.")
        )
    }

    func testContentListPresentationStateKeepsExistingContentVisibleDuringRefreshOrError() {
        XCTAssertEqual(
            ContentListPresentationState.resolve(
                loadState: .loading,
                isLoading: true,
                errorMessage: nil,
                searchQuery: "",
                hasLoadedContent: true,
                contentCount: 1
            ),
            .content
        )
        XCTAssertEqual(
            ContentListPresentationState.resolve(
                loadState: .failed("Refresh failed"),
                isLoading: false,
                errorMessage: "Refresh failed",
                searchQuery: "",
                hasLoadedContent: true,
                contentCount: 1
            ),
            .content
        )
    }

    func testContentListPresentationStateUsesSearchWhenQueryIsPresentAfterInitialLoad() {
        XCTAssertEqual(
            ContentListPresentationState.resolve(
                loadState: .loaded,
                isLoading: false,
                errorMessage: nil,
                searchQuery: "docs",
                hasLoadedContent: false,
                contentCount: 0
            ),
            .search
        )
    }

    func testContentListReadRecoveryCentralizesBeginSuccessAndEmptyFailureState() {
        XCTAssertEqual(
            ContentListReadRecovery.begin(hasVisibleContent: false),
            ContentListReadTransition(errorMessage: nil, loadState: .loading)
        )
        XCTAssertEqual(
            ContentListReadRecovery.begin(hasVisibleContent: true),
            ContentListReadTransition(errorMessage: nil, loadState: nil)
        )
        XCTAssertEqual(
            ContentListReadRecovery.success(),
            ContentListReadTransition(errorMessage: nil, loadState: .loaded)
        )

        let emptyFailure = ContentListReadRecovery.failure(
            error: APIClientError.missingToken,
            hasVisibleContent: false
        )
        XCTAssertEqual(emptyFailure?.errorMessage, "Authentication required. Please sign in.")
        XCTAssertEqual(emptyFailure?.loadState, .failed("Authentication required. Please sign in."))
        XCTAssertNil(
            ContentListReadRecovery.failure(
                error: APIClientError.missingToken,
                hasVisibleContent: true
            )
        )

        var errorMessage: String? = "Previous error"
        var loadState = ContentListLoadState.failed("Previous error")
        ContentListReadRecovery.success().apply(
            errorMessage: &errorMessage,
            loadState: &loadState
        )
        XCTAssertNil(errorMessage)
        XCTAssertEqual(loadState, .loaded)
    }
}

@MainActor
private final class TestLoadableViewModel: LoadableViewModel {
    var lastValue: String?
}
