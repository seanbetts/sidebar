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
}

@MainActor
private final class TestLoadableViewModel: LoadableViewModel {
    var lastValue: String?
}
