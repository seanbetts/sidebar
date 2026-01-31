import Foundation
import XCTest
@testable import sideBarShared

final class PendingShareStoreTests: XCTestCase {
    private let suiteName = "PendingShareStoreTests"

    override func tearDown() {
        if let defaults = UserDefaults(suiteName: suiteName) {
            defaults.removePersistentDomain(forName: suiteName)
        }
        super.tearDown()
    }

    func testEnqueueWebsiteStoresItem() {
        let store = makeStore()

        let item = store.enqueueWebsite(url: "https://example.com")

        XCTAssertNotNil(item)
        let loaded = store.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.url, "https://example.com")
    }

    func testEnqueueYouTubeStoresItem() {
        let store = makeStore()

        let item = store.enqueueYouTube(url: "https://youtube.com/watch?v=abc123")

        XCTAssertNotNil(item)
        let loaded = store.loadAll()
        XCTAssertEqual(loaded.first?.kind, .youtube)
    }

    func testEnqueueFileWritesData() throws {
        let store = makeStore()
        let payload = Data("hello".utf8)

        let item = store.enqueueFile(
            data: payload,
            filename: "sample.txt",
            mimeType: "text/plain",
            kind: .file
        )

        let resolved = item.flatMap { store.resolveFileURL(for: $0) }
        XCTAssertNotNil(resolved)
        let storedData = try resolved.map { try Data(contentsOf: $0) }
        XCTAssertEqual(storedData, payload)
    }

    func testRemoveDeletesItem() {
        let store = makeStore()
        let first = store.enqueueWebsite(url: "https://example.com")
        let second = store.enqueueWebsite(url: "https://example.org")

        store.remove(ids: [first?.id].compactMap { $0 })

        let remaining = store.loadAll()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.url, second?.url)
    }

    private func makeStore() -> PendingShareStore {
        let defaults = UserDefaults(suiteName: suiteName)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return PendingShareStore(baseDirectory: directory, userDefaults: defaults)
    }
}
