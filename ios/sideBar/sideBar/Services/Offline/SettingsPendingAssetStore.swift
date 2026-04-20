import Foundation
import sideBarShared

/// File-backed staging record for a pending profile-image upload.
public struct SettingsPendingAssetRecord: Codable, Equatable {
    public let data: Data
    public let contentType: String
    public let filename: String
}

/// File-backed staging store for pending profile-image uploads.
public final class SettingsPendingAssetStore {
    private let fileManager: FileManager
    private let rootDirectory: URL

    public init(fileManager: FileManager = .default, rootDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.rootDirectory = rootDirectory ?? Self.defaultRootDirectory(fileManager: fileManager)
        try? fileManager.createDirectory(at: self.rootDirectory, withIntermediateDirectories: true)
    }

    public func stageProfileImage(
        data: Data,
        contentType: String,
        filename: String
    ) throws -> String {
        let reference = UUID().uuidString
        let record = SettingsPendingAssetRecord(
            data: data,
            contentType: contentType,
            filename: filename
        )
        let url = fileURL(for: reference)
        let payload = try JSONEncoder().encode(record)
        fileManager.createFile(atPath: url.path, contents: payload)
        return reference
    }

    public func lookup(reference: String) throws -> SettingsPendingAssetRecord {
        let url = fileURL(for: reference)
        guard fileManager.fileExists(atPath: url.path) else {
            throw SettingsPendingAssetStoreError.missingReference
        }
        let payload = try Data(contentsOf: url)
        return try JSONDecoder().decode(SettingsPendingAssetRecord.self, from: payload)
    }

    public func delete(reference: String) throws {
        let url = fileURL(for: reference)
        guard fileManager.fileExists(atPath: url.path) else {
            throw SettingsPendingAssetStoreError.missingReference
        }
        try fileManager.removeItem(at: url)
    }

    private func fileURL(for reference: String) -> URL {
        rootDirectory.appendingPathComponent("\(reference).json", isDirectory: false)
    }

    private static func defaultRootDirectory(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent("sideBar", isDirectory: true)
            .appendingPathComponent("SettingsPendingAssets", isDirectory: true)
    }
}

enum SettingsPendingAssetStoreError: Error {
    case missingReference
}
