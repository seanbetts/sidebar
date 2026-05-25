import XCTest
@testable import sideBar
@testable import sideBarShared

extension PendingShareStoreTests {
    func testClearAllPreservesFileMetadataWhenRootDirectoryIsUnavailable() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "\(pendingShareStoreTestSuiteName).\(UUID().uuidString)"))
        let store = PendingShareStore(
            baseDirectory: nil,
            userDefaults: defaults,
            allowAppGroupFallback: false
        )
        let item = pendingFileItem(filePath: "pending-shares/\(UUID().uuidString)/missing-root.txt")
        store.writeMetadata([item])

        store.clearAll()

        XCTAssertEqual(store.loadAll().map(\.id), [item.id])
    }

    func testRemoveDropsInvalidMetadataAfterPartialBatchCleanupFailure() throws {
        let (store, directory) = try makeIsolatedStore()
        let validItem = try XCTUnwrap(store.enqueueFile(
            data: Data("payload".utf8), filename: "valid.txt", mimeType: "text/plain", kind: .file
        ))
        let validURL = try XCTUnwrap(store.resolveFileURL(for: validItem))
        let (invalidItem, target) = try makeLeafSymlinkScenario(directory: directory)
        store.replaceAll([validItem, invalidItem])

        store.remove(ids: [validItem.id, invalidItem.id])

        XCTAssertTrue(store.loadAll().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: validURL.path))
        XCTAssertNil(store.resolveFileURL(for: invalidItem))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    }

    func testRemoveTreatsDuplicateStagedPathBatchItemsAsCleanedTogether() throws {
        let (store, _) = try makeIsolatedStore()
        let first = try XCTUnwrap(store.enqueueFile(
            data: Data("payload".utf8), filename: "shared.txt", mimeType: "text/plain", kind: .file
        ))
        let fileURL = try XCTUnwrap(store.resolveFileURL(for: first))
        let duplicate = PendingShareItem(
            id: UUID(),
            kind: .file,
            createdAt: first.createdAt,
            filePath: first.filePath,
            filename: first.filename,
            mimeType: first.mimeType
        )
        store.writeMetadata([first, duplicate])

        store.remove(ids: [first.id, duplicate.id])

        XCTAssertTrue(store.loadAll().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testRemoveDoesNotRequireStagedCleanupForNonFileKindWithLegacyFilePath() throws {
        let (store, _) = try makeIsolatedStore()
        let item = PendingShareItem(
            id: UUID(),
            kind: .website,
            createdAt: Date(),
            url: "https://example.com",
            filePath: "../legacy.txt"
        )
        store.writeMetadata([item])

        store.remove(ids: [item.id])

        XCTAssertTrue(store.loadAll().isEmpty)
    }
}
