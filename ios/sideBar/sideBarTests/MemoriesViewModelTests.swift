import XCTest
@testable import sideBar

@MainActor
final class MemoriesViewModelTests: XCTestCase {
    func testLoadUsesCacheOnFailure() async {
        let cached = [makeMemory(id: "cached")]
        let cache = TestCacheClient()
        cache.set(key: CacheKeys.memoriesList, value: cached, ttlSeconds: 60)
        let viewModel = MemoriesViewModel(
            api: MockMemoriesAPI(listResult: .failure(MockError.forced)),
            cache: cache
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.items.first?.id, "cached")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testSelectMemoryUsesListItem() async {
        let memory = makeMemory(id: "mem-1")
        let cache = TestCacheClient()
        let viewModel = MemoriesViewModel(
            api: MockMemoriesAPI(listResult: .success([memory])),
            cache: cache
        )

        await viewModel.load()
        await viewModel.selectMemory(id: "mem-1")

        XCTAssertEqual(viewModel.active?.id, "mem-1")
        XCTAssertEqual(viewModel.selectedMemoryId, "mem-1")
    }
}

private enum MockError: Error {
    case forced
}

private struct MockMemoriesAPI: MemoriesProviding {
    let listResult: Result<[MemoryItem], Error>
    let getResult: Result<MemoryItem, Error>

    init(
        listResult: Result<[MemoryItem], Error>,
        getResult: Result<MemoryItem, Error> = .failure(MockError.forced)
    ) {
        self.listResult = listResult
        self.getResult = getResult
    }

    func list() async throws -> [MemoryItem] {
        try listResult.get()
    }

    func get(id: String) async throws -> MemoryItem {
        _ = id
        return try getResult.get()
    }
}

private func makeMemory(id: String) -> MemoryItem {
    MemoryItem(
        id: id,
        path: "/memories/example.md",
        content: "Hello",
        createdAt: "2024-05-01T12:00:00Z",
        updatedAt: "2024-05-02T12:00:00Z"
    )
}
