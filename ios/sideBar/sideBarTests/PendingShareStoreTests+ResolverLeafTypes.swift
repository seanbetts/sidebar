import XCTest
@testable import sideBar
@testable import sideBarShared

extension PendingShareStoreTests {
    func testDirectoryLeafIsRejectedAndNotDeletedOrPreparedForUpload() throws {
        let (store, directory) = try makeIsolatedStore()
        let uuid = UUID().uuidString
        let root = directory.appendingPathComponent("pending-shares", isDirectory: true)
        let payloadDirectory = root.appendingPathComponent("\(uuid)/payload", isDirectory: true)
        let keepFile = payloadDirectory.appendingPathComponent("keep.txt")
        try FileManager.default.createDirectory(at: payloadDirectory, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: keepFile)
        let item = pendingFileItem(filePath: "pending-shares/\(uuid)/payload")
        store.replaceAll([item])
        let tempUploadDirectoriesBefore = pendingShareUploadTempDirectories()

        XCTAssertNil(store.resolveFileURL(for: item))
        XCTAssertNil(store.prepareFileForUpload(for: item))
        store.remove(ids: [item.id])

        XCTAssertEqual(store.loadAll().map(\.id), [item.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: payloadDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: keepFile.path))
        XCTAssertEqual(pendingShareUploadTempDirectories(), tempUploadDirectoriesBefore)
    }

    private func pendingShareUploadTempDirectories() -> Set<String> {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "pending-share-uploads",
            isDirectory: true
        )
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return Set(contents.map(\.lastPathComponent))
    }
}
