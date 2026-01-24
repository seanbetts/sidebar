import XCTest
@testable import sideBar

@MainActor
final class LoadableStateTests: XCTestCase {
    func testLoadingStateComputedProperties() {
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
}

@MainActor
private final class TestLoadableViewModel: LoadableViewModel {
    var lastValue: String?
}
