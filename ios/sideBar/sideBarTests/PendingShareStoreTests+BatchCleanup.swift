import XCTest
@testable import sideBar
@testable import sideBarShared

extension PendingShareStoreTests {
    func testRemoveUpdatesMetadataAfterPartialBatchCleanupFailure() throws {
        let (store, directory) = try makeIsolatedStore()
        let validItem = try XCTUnwrap(store.enqueueFile(
            data: Data("payload".utf8), filename: "valid.txt", mimeType: "text/plain", kind: .file
        ))
        let validURL = try XCTUnwrap(store.resolveFileURL(for: validItem))
        let (invalidItem, target) = try makeLeafSymlinkScenario(directory: directory)
        store.replaceAll([validItem, invalidItem])

        store.remove(ids: [validItem.id, invalidItem.id])

        XCTAssertEqual(store.loadAll().map(\.id), [invalidItem.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: validURL.path))
        XCTAssertNil(store.resolveFileURL(for: invalidItem))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    }
}
