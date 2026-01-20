import Foundation

public struct TemporaryFileStore {
    public static let shared = TemporaryFileStore()

    private let directory: URL

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.directory = base.appendingPathComponent("sideBar-temp", isDirectory: true)
        }
    }

    public func store(data: Data, filename: String) throws -> URL {
        let url = try makeURL(filename: filename)
        try ensureDirectory()
        try data.write(to: url, options: .atomic)
        return url
    }

    public func store(text: String, filename: String) throws -> URL {
        let data = Data(text.utf8)
        return try store(data: data, filename: filename)
    }

    private func ensureDirectory() throws {
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func makeURL(filename: String) throws -> URL {
        let trimmed = filename.trimmed
        let safeName = trimmed.isEmpty ? "file" : trimmed
        let unique = "\(UUID().uuidString)-\(safeName)"
        return directory.appendingPathComponent(unique, isDirectory: false)
    }
}
