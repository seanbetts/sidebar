import Foundation
import XCTest
@testable import sideBar
@testable import sideBarShared

let pendingShareStoreTestSuiteName = "PendingShareStoreTests"

func makeStore() -> PendingShareStore {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    return PendingShareStore(baseDirectory: directory, userDefaults: UserDefaults(suiteName: pendingShareStoreTestSuiteName))
}

func makeIsolatedStore(
    stagedFileMutationLock: ((URL, @escaping () -> Bool) -> Bool)? = nil,
    idGenerator: @escaping () -> UUID = UUID.init
) throws -> (PendingShareStore, URL) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let defaults = try XCTUnwrap(UserDefaults(suiteName: "\(pendingShareStoreTestSuiteName).\(UUID().uuidString)"))
    let store = PendingShareStore(
        baseDirectory: directory,
        userDefaults: defaults,
        allowAppGroupFallback: false,
        stagedFileMutationLock: stagedFileMutationLock,
        idGenerator: idGenerator
    )
    return (store, directory)
}

func assertRemovalRejectsSymlinkedPath(
    _ makeScenario: (URL) throws -> (PendingShareItem, URL)
) throws {
    let (store, directory) = try makeIsolatedStore()
    let (item, target) = try makeScenario(directory)
    store.replaceAll([item])
    store.remove(ids: [item.id])
    XCTAssertNil(store.resolveFileURL(for: item))
    XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    XCTAssertTrue(store.loadAll().isEmpty)
}

func routePendingShareItem(
    _ item: PendingShareItem,
    isOffline: @escaping () -> Bool = { false },
    saveWebsite: @escaping (String) async -> Bool = { _ in false },
    ingestYouTube: @escaping (String) async -> String? = { _ in nil },
    prepareFileForUpload: @escaping (PendingShareItem) -> URL? = { _ in nil },
    startUpload: @escaping (URL) -> Bool = { _ in false }
) async -> Bool {
    await shouldKeepPendingShareItem(
        item, isOffline: isOffline, saveWebsite: saveWebsite, ingestYouTube: ingestYouTube,
        prepareFileForUpload: prepareFileForUpload, startUpload: startUpload
    )
}

func makeLeafSymlinkScenario(directory: URL) throws -> (PendingShareItem, URL) {
    let root = directory.appendingPathComponent("pending-shares", isDirectory: true)
    let uuid = UUID().uuidString
    let target = root.appendingPathComponent("manual/leaf-target.txt")
    try FileManager.default.createDirectory(at: root.appendingPathComponent(uuid), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("keep leaf".utf8).write(to: target)
    try FileManager.default.createSymbolicLink(
        at: root.appendingPathComponent("\(uuid)/link.txt"), withDestinationURL: target
    )
    return (pendingFileItem(filePath: "pending-shares/\(uuid)/link.txt"), target)
}

func makeItemDirectorySymlinkScenario(directory: URL) throws -> (PendingShareItem, URL) {
    let root = directory.appendingPathComponent("pending-shares", isDirectory: true)
    let uuid = UUID().uuidString
    let target = root.appendingPathComponent("manual")
    let targetFile = target.appendingPathComponent("target.txt")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    try Data("keep directory".utf8).write(to: targetFile)
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(uuid), withDestinationURL: target)
    return (pendingFileItem(filePath: "pending-shares/\(uuid)/target.txt"), targetFile)
}

func makeRootSymlinkScenario(directory: URL) throws -> (PendingShareItem, URL) {
    let target = directory.appendingPathComponent("root-target")
    let uuid = UUID().uuidString
    let targetFile = target.appendingPathComponent("\(uuid)/target.txt")
    try FileManager.default.createDirectory(at: targetFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("keep root".utf8).write(to: targetFile)
    try FileManager.default.createSymbolicLink(
        at: directory.appendingPathComponent("pending-shares"), withDestinationURL: target
    )
    return (pendingFileItem(filePath: "pending-shares/\(uuid)/target.txt"), targetFile)
}

func pendingWebsiteItem(createdAt: Date = Date(), retryCount: Int = 0, nextRetryAt: Date? = nil) -> PendingShareItem {
    PendingShareItem(
        id: UUID(), kind: .website, createdAt: createdAt, url: "https://example.com", retryCount: retryCount, nextRetryAt: nextRetryAt
    )
}

func pendingYouTubeItem() -> PendingShareItem {
    PendingShareItem(id: UUID(), kind: .youtube, createdAt: Date(), url: "https://www.youtube.com/watch?v=abc123xyzAA")
}

func pendingFileItem(filePath: String = "pending-shares/\(UUID().uuidString)/file.pdf") -> PendingShareItem {
    PendingShareItem(id: UUID(), kind: .file, createdAt: Date(), filePath: filePath)
}
