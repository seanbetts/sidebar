import XCTest
import sideBarShared
@testable import sideBar
import SwiftUI

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

    func testCachedScratchpadReturnsCachedValue() async {
        let cached = ScratchpadResponse(id: "s1", title: "Scratchpad", content: "Cached", updatedAt: nil)
        let cache = TestCacheClient()
        cache.set(key: CacheKeys.scratchpad, value: cached, ttlSeconds: 60)
        let viewModel = ScratchpadViewModel(
            api: MockScratchpadAPI(getResult: .failure(MockError.forced), updateResult: .failure(MockError.forced)),
            cache: cache
        )

        XCTAssertEqual(viewModel.cachedScratchpad()?.content, "Cached")
    }

    func testOpeningScratchpadPopoverDoesNotTriggerSaveWithoutUserEdits() async {
        let api = RecordingScratchpadAPI(
            getResponse: ScratchpadResponse(
                id: "scratchpad-1",
                title: ScratchpadConstants.title,
                content: "\(ScratchpadConstants.title)\n\nHello\n",
                updatedAt: nil
            )
        )
        let cache = TestCacheClient()
        let store = ScratchpadStore()

        mount(
            ScratchpadPopoverView(
                api: api,
                cache: cache,
                scratchpadStore: store
            ),
            frame: CGRect(x: 0, y: 0, width: 390, height: 844)
        )

        await waitUntil(timeout: .seconds(3)) {
            api.getCallCount == 1
        }

        try? await Task.sleep(for: .milliseconds(1400))

        XCTAssertEqual(api.updateCallCount, 0)
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

@MainActor
private final class RecordingScratchpadAPI: ScratchpadProviding {
    private(set) var getCallCount = 0
    private(set) var updateCallCount = 0

    let getResponse: ScratchpadResponse

    init(getResponse: ScratchpadResponse) {
        self.getResponse = getResponse
    }

    func get() async throws -> ScratchpadResponse {
        getCallCount += 1
        return getResponse
    }

    func update(content: String, mode: ScratchpadMode?) async throws -> ScratchpadResponse {
        _ = content
        _ = mode
        updateCallCount += 1
        return getResponse
    }
}
