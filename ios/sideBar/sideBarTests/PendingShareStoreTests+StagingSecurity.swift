import Foundation
import XCTest
@testable import sideBarShared
@testable import sideBar

@MainActor
extension PendingShareStoreTests {
    func testEnqueueFileFailsWhenPendingShareRootIsSymlink() throws {
        let (store, directory) = try makeIsolatedStore()
        let target = directory.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("pending-shares", isDirectory: true),
            withDestinationURL: target
        )

        let item = store.enqueueFile(
            data: Data("payload".utf8),
            filename: "sample.txt",
            mimeType: "text/plain",
            kind: .file
        )

        XCTAssertNil(item)
        XCTAssertTrue(store.loadAll().isEmpty)
        XCTAssertTrue((try FileManager.default.contentsOfDirectory(atPath: target.path)).isEmpty)
    }

    func testResolveFileURLRejectsAbsoluteAndTraversalPaths() throws {
        let (store, directory) = try makeIsolatedStore()
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("pending-shares/\(UUID().uuidString)"),
            withIntermediateDirectories: true
        )
        let invalidPaths = [
            "/tmp/escaped.txt",
            "pending-shares/\(UUID().uuidString)/../escaped.txt",
            "pending-shares/file.txt",
            "pending-shares/\(UUID().uuidString)/",
            "pending-shares/\(UUID().uuidString)/nested/file.txt"
        ]
        for path in invalidPaths {
            let item = PendingShareItem(
                id: UUID(), kind: .file, createdAt: Date(),
                filePath: path, filename: "escaped.txt", mimeType: "text/plain"
            )
            XCTAssertNil(store.resolveFileURL(for: item))
        }
    }

    func testRemoveDeletesStagedFileAndContainingDirectory() throws {
        let store = makeStore()
        let item = try XCTUnwrap(store.enqueueFile(
            data: Data("payload".utf8),
            filename: "sample.txt",
            mimeType: "text/plain",
            kind: .file
        ))
        let fileURL = try XCTUnwrap(store.resolveFileURL(for: item))
        let itemDirectory = fileURL.deletingLastPathComponent()

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: itemDirectory.path))

        store.remove(ids: [item.id])

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: itemDirectory.path))
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func testRemoveDoesNotDeleteOutsidePendingShareRootForInvalidPath() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let outside = directory.appendingPathComponent("outside.txt")
        try Data("do not delete".utf8).write(to: outside)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "\(pendingShareStoreTestSuiteName).\(UUID().uuidString)"))
        let store = PendingShareStore(
            baseDirectory: directory,
            userDefaults: defaults,
            allowAppGroupFallback: false
        )
        let item = PendingShareItem(
            id: UUID(), kind: .file, createdAt: Date(), filePath: "../outside.txt",
            filename: "outside.txt", mimeType: "text/plain"
        )

        store.replaceAll([item])
        store.remove(ids: [item.id])

        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func testRemoveRejectsSymlinkStagedPathsWithoutDeletingTargets() throws {
        try assertRemovalRejectsSymlinkedPath(makeLeafSymlinkScenario)
        try assertRemovalRejectsSymlinkedPath(makeItemDirectorySymlinkScenario)
        try assertRemovalRejectsSymlinkedPath(makeRootSymlinkScenario)
    }

    func testRemoveValidatesAndDeletesInsideStagedFileCriticalSection() throws {
        var operation: (() -> Bool)?
        let (store, directory) = try makeIsolatedStore(stagedFileMutationLock: { _, body in operation = body; return true })
        let uuid = UUID().uuidString
        let fileURL = directory.appendingPathComponent("pending-shares/\(uuid)/payload.txt")
        let target = directory.appendingPathComponent("pending-shares/manual/target.txt")
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("payload".utf8).write(to: fileURL)
        try Data("target".utf8).write(to: target)
        let item = pendingFileItem(filePath: "pending-shares/\(uuid)/payload.txt")

        store.replaceAll([item])
        store.remove(ids: [item.id])
        try FileManager.default.removeItem(at: fileURL)
        try FileManager.default.createSymbolicLink(at: fileURL, withDestinationURL: target)
        _ = operation?()

        XCTAssertNil(store.resolveFileURL(for: item))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: fileURL.path))
    }

    func testPrepareFileForUploadCopiesWhileLockedToTemporaryURL() throws {
        var copiedWhileLocked = false
        let (store, _) = try makeIsolatedStore(stagedFileMutationLock: { _, body in
            let result = body()
            copiedWhileLocked = true
            return result
        })
        let item = try XCTUnwrap(store.enqueueFile(
            data: Data("payload".utf8), filename: "sample.txt", mimeType: "text/plain", kind: .file
        ))
        let stagedURL = try XCTUnwrap(store.resolveFileURL(for: item))

        let preparedURL = try XCTUnwrap(store.prepareFileForUpload(for: item))

        XCTAssertTrue(copiedWhileLocked)
        XCTAssertNotEqual(preparedURL.path, stagedURL.path)
        XCTAssertFalse(preparedURL.path.contains("/pending-shares/"))
        XCTAssertEqual(try Data(contentsOf: preparedURL), Data("payload".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagedURL.path))
        XCTAssertTrue(preparedURL.path.hasPrefix(FileManager.default.temporaryDirectory.path))
    }

    func testRemoveLeavesQueuedFileWhenStagedFileLockDoesNotRun() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "\(pendingShareStoreTestSuiteName).\(UUID().uuidString)"))
        let writer = PendingShareStore(baseDirectory: directory, userDefaults: defaults, allowAppGroupFallback: false)
        let store = PendingShareStore(
            baseDirectory: directory,
            userDefaults: defaults,
            allowAppGroupFallback: false,
            stagedFileMutationLock: { _, _ in true }
        )
        let item = try XCTUnwrap(writer.enqueueFile(
            data: Data("payload".utf8), filename: "locked.txt", mimeType: "text/plain", kind: .file
        ))
        let stagedURL = try XCTUnwrap(store.resolveFileURL(for: item))

        store.remove(ids: [item.id])

        XCTAssertEqual(store.loadAll().map(\.id), [item.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagedURL.path))
    }

    func testReplaceAllRemovesDroppedFileItemStagedFile() throws {
        let (store, _) = try makeIsolatedStore()
        let fileItem = try XCTUnwrap(store.enqueueFile(
            data: Data("payload".utf8), filename: "replace.txt", mimeType: "text/plain", kind: .file
        ))
        let stagedURL = try XCTUnwrap(store.resolveFileURL(for: fileItem))
        let itemDirectory = stagedURL.deletingLastPathComponent()

        store.replaceAll([])

        XCTAssertTrue(store.loadAll().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: itemDirectory.path))
    }

    func testReplaceAllCleaningRemovedStagedFilesDeletesDroppedFileItem() throws {
        let (store, _) = try makeIsolatedStore()
        let fileItem = try XCTUnwrap(store.enqueueFile(
            data: Data("payload".utf8), filename: "replayed.txt", mimeType: "text/plain", kind: .file
        ))
        let websiteItem = try XCTUnwrap(store.enqueueWebsite(url: "https://example.com"))
        let stagedURL = try XCTUnwrap(store.resolveFileURL(for: fileItem))
        let itemDirectory = stagedURL.deletingLastPathComponent()

        XCTAssertTrue(store.replaceAllCleaningRemovedStagedFiles([websiteItem]))

        let remaining = store.loadAll()
        XCTAssertEqual(remaining.map(\.id), [websiteItem.id])
        XCTAssertEqual(remaining.first?.url, websiteItem.url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: itemDirectory.path))
    }

    func testConsumeAllDeletesQueuedFileStaging() throws {
        let store = makeStore()
        let item = try XCTUnwrap(store.enqueueFile(
            data: Data("payload".utf8), filename: "consume.txt", mimeType: "text/plain", kind: .file
        ))
        let stagedURL = try XCTUnwrap(store.resolveFileURL(for: item))
        let itemDirectory = stagedURL.deletingLastPathComponent()

        let consumed = store.consumeAll()

        XCTAssertEqual(consumed.map(\.id), [item.id])
        XCTAssertTrue(store.loadAll().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: itemDirectory.path))
    }

    func testConsumeAllKeepsFileMetadataWhenCleanupLockDoesNotRun() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "\(pendingShareStoreTestSuiteName).\(UUID().uuidString)"))
        let writer = PendingShareStore(baseDirectory: directory, userDefaults: defaults, allowAppGroupFallback: false)
        let item = try XCTUnwrap(writer.enqueueFile(
            data: Data("payload".utf8), filename: "locked.txt", mimeType: "text/plain", kind: .file
        ))
        let stagedURL = try XCTUnwrap(writer.resolveFileURL(for: item))
        let store = PendingShareStore(
            baseDirectory: directory,
            userDefaults: defaults,
            allowAppGroupFallback: false,
            stagedFileMutationLock: { _, _ in true }
        )

        let consumed = store.consumeAll()

        XCTAssertTrue(consumed.isEmpty)
        XCTAssertEqual(store.loadAll().map(\.id), [item.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagedURL.path))
    }
}
