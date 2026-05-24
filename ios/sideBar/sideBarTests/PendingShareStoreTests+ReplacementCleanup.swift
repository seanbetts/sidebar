import XCTest
@testable import sideBar
@testable import sideBarShared

extension PendingShareStoreTests {
    func testReplaceAllKeepsStagedFileWhenReplacementReferencesSamePathWithDifferentID() throws {
        let (store, _) = try makeIsolatedStore()
        let fileItem = try XCTUnwrap(store.enqueueFile(
            data: Data("payload".utf8), filename: "retained.txt", mimeType: "text/plain", kind: .file
        ))
        let stagedURL = try XCTUnwrap(store.resolveFileURL(for: fileItem))
        let replacement = PendingShareItem(
            id: UUID(),
            kind: .file,
            createdAt: fileItem.createdAt,
            filePath: fileItem.filePath,
            filename: fileItem.filename,
            mimeType: fileItem.mimeType
        )

        XCTAssertTrue(store.replaceAllCleaningRemovedStagedFiles([replacement]))

        let loaded = try XCTUnwrap(store.loadAll().first)
        XCTAssertEqual(loaded.id, replacement.id)
        XCTAssertEqual(loaded.filePath, fileItem.filePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagedURL.path))
    }
}
