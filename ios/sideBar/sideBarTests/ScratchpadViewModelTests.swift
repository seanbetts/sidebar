import XCTest
@testable import sideBar

@MainActor
final class ScratchpadViewModelTests: XCTestCase {
    func testLoadUsesCacheOnFailure() async {
        let cached = ScratchpadResponse(id: "s1", title: "Scratchpad", content: "Cached", updatedAt: nil)
        let cache = TestCacheClient()
        cache.set(key: CacheKeys.scratchpad, value: cached, ttlSeconds: 60)
        let viewModel = ScratchpadViewModel(
            api: MockScratchpadAPI(getResult: .failure(MockError.forced), updateResult: .failure(MockError.forced)),
            cache: cache
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.scratchpad?.content, "Cached")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testUpdateCachesResponse() async {
        let updated = ScratchpadResponse(id: "s1", title: "Scratchpad", content: "Updated", updatedAt: nil)
        let cache = TestCacheClient()
        let viewModel = ScratchpadViewModel(
            api: MockScratchpadAPI(getResult: .failure(MockError.forced), updateResult: .success(updated)),
            cache: cache
        )

        await viewModel.update(content: "Updated", mode: .replace)

        let cached: ScratchpadResponse? = cache.get(key: CacheKeys.scratchpad)
        XCTAssertEqual(cached?.content, "Updated")
        XCTAssertEqual(viewModel.scratchpad?.content, "Updated")
    }
}

private enum MockError: Error {
    case forced
}

private struct MockScratchpadAPI: ScratchpadProviding {
    let getResult: Result<ScratchpadResponse, Error>
    let updateResult: Result<ScratchpadResponse, Error>

    func get() async throws -> ScratchpadResponse {
        try getResult.get()
    }

    func update(content: String, mode: ScratchpadMode?) async throws -> ScratchpadResponse {
        _ = content
        _ = mode
        return try updateResult.get()
    }
}
