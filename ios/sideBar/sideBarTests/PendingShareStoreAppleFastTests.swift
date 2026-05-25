import Foundation
import XCTest
@testable import sideBarShared

private final class AppleFastFailingRemoveFileManager: FileManager {
    var failingRemovePath: String?

    override func removeItem(at URL: URL) throws {
        if URL.path == failingRemovePath {
            throw CocoaError(.fileWriteUnknown)
        }
        try super.removeItem(at: URL)
    }
}

final class PendingShareStoreAppleFastTests: XCTestCase {
    func testResolverRejectsUnsafeSymlinkAndDirectoryLeafPaths() throws {
        let fixture = try makeStore()
        let store = fixture.store
        let directory = fixture.directory
        let uuid = UUID().uuidString
        let root = directory.appendingPathComponent("pending-shares", isDirectory: true)
        let itemDirectory = root.appendingPathComponent(uuid, isDirectory: true)
        let regularFile = itemDirectory.appendingPathComponent("payload.txt")
        let leafDirectory = itemDirectory.appendingPathComponent("payload-dir", isDirectory: true)
        let leafSymlink = itemDirectory.appendingPathComponent("link.txt")
        let symlinkTarget = root.appendingPathComponent("manual/target.txt")
        try FileManager.default.createDirectory(at: itemDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: leafDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: symlinkTarget.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("payload".utf8).write(to: regularFile)
        try Data("target".utf8).write(to: symlinkTarget)
        try FileManager.default.createSymbolicLink(at: leafSymlink, withDestinationURL: symlinkTarget)

        XCTAssertNotNil(store.resolveFileURL(for: fileItem(filePath: "pending-shares/\(uuid)/payload.txt")))
        XCTAssertNil(store.resolveFileURL(for: fileItem(filePath: "/tmp/escaped.txt")))
        XCTAssertNil(store.resolveFileURL(for: fileItem(filePath: "pending-shares/\(uuid)/../escaped.txt")))
        XCTAssertNil(store.resolveFileURL(for: fileItem(filePath: "pending-shares/\(uuid)/nested/payload.txt")))
        XCTAssertNil(store.resolveFileURL(for: fileItem(filePath: "pending-shares/\(uuid)/link.txt")))
        XCTAssertNil(store.resolveFileURL(for: fileItem(filePath: "pending-shares/\(uuid)/payload-dir")))
    }

    func testStagedWritesRejectDanglingLeafSymlinks() throws {
        let dataItemID = UUID()
        let copyItemID = UUID()
        let ids = [dataItemID, copyItemID]
        var idIndex = 0
        let fixture = try makeStore(idGenerator: {
            defer { idIndex += 1 }
            return ids[idIndex]
        })
        let store = fixture.store
        let directory = fixture.directory
        let root = directory.appendingPathComponent("pending-shares", isDirectory: true)
        let dataDirectory = root.appendingPathComponent(dataItemID.uuidString, isDirectory: true)
        let copyDirectory = root.appendingPathComponent(copyItemID.uuidString, isDirectory: true)
        let dataTarget = directory.appendingPathComponent("outside-data.txt")
        let copyTarget = directory.appendingPathComponent("outside-copy.txt")
        let source = directory.appendingPathComponent("source.txt")
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: copyDirectory, withIntermediateDirectories: true)
        try Data("source".utf8).write(to: source)
        try FileManager.default.createSymbolicLink(
            at: dataDirectory.appendingPathComponent("dangling-data.txt"),
            withDestinationURL: dataTarget
        )
        try FileManager.default.createSymbolicLink(
            at: copyDirectory.appendingPathComponent("dangling-copy.txt"),
            withDestinationURL: copyTarget
        )

        let dataItem = store.enqueueFile(
            data: Data("payload".utf8),
            filename: "dangling-data.txt",
            mimeType: "text/plain",
            kind: .file
        )
        let copyItem = store.enqueueFile(
            at: source,
            filename: "dangling-copy.txt",
            mimeType: "text/plain",
            kind: .file
        )

        XCTAssertNil(dataItem)
        XCTAssertNil(copyItem)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dataTarget.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: copyTarget.path))
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func testCleanupFailureRetainsMetadataAndResolverRejectionDropsMetadata() throws {
        let failingFileManager = AppleFastFailingRemoveFileManager()
        let writerFixture = try makeStore()
        let writer = writerFixture.store
        let directory = writerFixture.directory
        let defaults = writerFixture.defaults
        let removable = try XCTUnwrap(writer.enqueueFile(
            data: Data("payload".utf8),
            filename: "removable.txt",
            mimeType: "text/plain",
            kind: .file
        ))
        let removableURL = try XCTUnwrap(writer.resolveFileURL(for: removable))
        let rejected = try makeLeafSymlinkItem(directory: directory, filename: "rejected.txt")
        writer.writeMetadata([removable, rejected.item])
        let store = PendingShareStore(
            baseDirectory: directory,
            userDefaults: defaults,
            allowAppGroupFallback: false,
            fileManager: failingFileManager
        )
        failingFileManager.failingRemovePath = removableURL.path

        store.remove(ids: [removable.id, rejected.item.id])

        XCTAssertEqual(store.loadAll().map(\.id), [removable.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: removableURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rejected.target.path))
    }

    func testReplacementCleanupHandlesPathChangesAndSharedStagedPaths() throws {
        let store = try makeStore().store
        let original = try XCTUnwrap(store.enqueueFile(
            data: Data("old".utf8),
            filename: "old.txt",
            mimeType: "text/plain",
            kind: .file
        ))
        let retained = try XCTUnwrap(store.enqueueFile(
            data: Data("retained".utf8),
            filename: "retained.txt",
            mimeType: "text/plain",
            kind: .file
        ))
        let oldURL = try XCTUnwrap(store.resolveFileURL(for: original))
        let retainedURL = try XCTUnwrap(store.resolveFileURL(for: retained))
        let replacement = PendingShareItem(
            id: original.id,
            kind: .file,
            createdAt: original.createdAt,
            filePath: retained.filePath,
            filename: retained.filename,
            mimeType: retained.mimeType
        )

        XCTAssertTrue(store.replaceAllCleaningRemovedStagedFiles([replacement]))

        XCTAssertEqual(store.loadAll().map(\.id), [replacement.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: retainedURL.path))
    }

    func testDuplicateStagedPathItemsAreCleanedTogetherForRemoveAndReplacement() throws {
        let removeStore = try makeStore().store
        let removeFirst = try XCTUnwrap(removeStore.enqueueFile(
            data: Data("payload".utf8),
            filename: "remove-shared.txt",
            mimeType: "text/plain",
            kind: .file
        ))
        let removeURL = try XCTUnwrap(removeStore.resolveFileURL(for: removeFirst))
        let removeDuplicate = duplicateFileItem(from: removeFirst)
        removeStore.writeMetadata([removeFirst, removeDuplicate])

        removeStore.remove(ids: [removeFirst.id, removeDuplicate.id])

        XCTAssertTrue(removeStore.loadAll().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: removeURL.path))

        let replaceStore = try makeStore().store
        let replaceFirst = try XCTUnwrap(replaceStore.enqueueFile(
            data: Data("payload".utf8),
            filename: "replace-shared.txt",
            mimeType: "text/plain",
            kind: .file
        ))
        let replaceURL = try XCTUnwrap(replaceStore.resolveFileURL(for: replaceFirst))
        let replaceDuplicate = duplicateFileItem(from: replaceFirst)
        replaceStore.writeMetadata([replaceFirst, replaceDuplicate])

        XCTAssertTrue(replaceStore.replaceAllCleaningRemovedStagedFiles([]))

        XCTAssertTrue(replaceStore.loadAll().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: replaceURL.path))
    }

    func testReplacementCleanupRetainsMetadataWhenSameIDDropsStagedReference() throws {
        let failingFileManager = AppleFastFailingRemoveFileManager()
        let writerFixture = try makeStore()
        let writer = writerFixture.store
        let directory = writerFixture.directory
        let defaults = writerFixture.defaults
        let original = try XCTUnwrap(writer.enqueueFile(
            data: Data("old".utf8),
            filename: "old.txt",
            mimeType: "text/plain",
            kind: .file
        ))
        let oldURL = try XCTUnwrap(writer.resolveFileURL(for: original))
        let store = PendingShareStore(
            baseDirectory: directory,
            userDefaults: defaults,
            allowAppGroupFallback: false,
            fileManager: failingFileManager
        )
        failingFileManager.failingRemovePath = oldURL.path
        let replacement = PendingShareItem(id: original.id, kind: .website, createdAt: Date(), url: "https://example.com")

        XCTAssertFalse(store.replaceAllCleaningRemovedStagedFiles([replacement]))

        XCTAssertEqual(store.loadAll().map(\.id), [original.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.path))
    }

    func testBatchCleanupProgressUpdatesMetadataForSucceededItems() throws {
        let fixture = try makeStore()
        let store = fixture.store
        let directory = fixture.directory
        let valid = try XCTUnwrap(store.enqueueFile(
            data: Data("payload".utf8),
            filename: "valid.txt",
            mimeType: "text/plain",
            kind: .file
        ))
        let validURL = try XCTUnwrap(store.resolveFileURL(for: valid))
        let invalid = try makeLeafSymlinkItem(directory: directory, filename: "invalid.txt")
        store.writeMetadata([valid, invalid.item])

        store.remove(ids: [valid.id, invalid.item.id])

        XCTAssertTrue(store.loadAll().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: validURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: invalid.target.path))
    }

    func testNonFileKindWithLegacyFilePathDoesNotRequireStagedCleanup() throws {
        let store = try makeStore().store
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

    private func makeStore(idGenerator: @escaping () -> UUID = UUID.init) throws -> StoreFixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "PendingShareStoreAppleFastTests.\(UUID().uuidString)"))
        let store = PendingShareStore(
            baseDirectory: directory,
            userDefaults: defaults,
            allowAppGroupFallback: false,
            idGenerator: idGenerator
        )
        return StoreFixture(store: store, directory: directory, defaults: defaults)
    }

    private struct StoreFixture {
        let store: PendingShareStore
        let directory: URL
        let defaults: UserDefaults
    }

    private func fileItem(filePath: String) -> PendingShareItem {
        PendingShareItem(id: UUID(), kind: .file, createdAt: Date(), filePath: filePath)
    }

    private func duplicateFileItem(from item: PendingShareItem) -> PendingShareItem {
        PendingShareItem(
            id: UUID(),
            kind: item.kind,
            createdAt: item.createdAt,
            filePath: item.filePath,
            filename: item.filename,
            mimeType: item.mimeType
        )
    }

    private func makeLeafSymlinkItem(
        directory: URL,
        filename: String
    ) throws -> (item: PendingShareItem, target: URL) {
        let root = directory.appendingPathComponent("pending-shares", isDirectory: true)
        let uuid = UUID().uuidString
        let target = root.appendingPathComponent("manual/\(filename)")
        let link = root.appendingPathComponent("\(uuid)/\(filename)")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        return (fileItem(filePath: "pending-shares/\(uuid)/\(filename)"), target)
    }
}
