import Darwin
import Foundation

struct PendingShareStagedFileOperations {
    static func withDefaultLock(baseDirectory: URL, operation: @escaping () -> Bool) -> Bool {
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let lockURL = baseDirectory.appendingPathComponent(".pending-share-staged-files.lock", isDirectory: false)
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { return false }
        defer { flock(descriptor, LOCK_UN) }
        return operation()
    }

    static func copyPreparedUploadFile(from fileURL: URL, filename: String) -> URL? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pending-share-uploads", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = directory.appendingPathComponent(filename, isDirectory: false)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: fileURL, to: destination)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: directory)
            return nil
        }
    }

    static func stagingDirectory(
        baseDirectory: URL,
        directoryName: String,
        itemId: UUID,
        fileManager: FileManager
    ) -> URL? {
        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let root = baseDirectory.appendingPathComponent(directoryName, isDirectory: true).standardizedFileURL
        guard createAndValidateDirectory(root, fileManager: fileManager) else { return nil }

        let directory = root.appendingPathComponent(itemId.uuidString, isDirectory: true).standardizedFileURL
        guard directory.deletingLastPathComponent().path == root.path else { return nil }
        guard createAndValidateDirectory(directory, fileManager: fileManager) else { return nil }
        return directory
    }

    static func writeStagedFile(
        data: Data,
        filename: String,
        itemId: UUID,
        baseDirectory: URL,
        directoryName: String,
        fileManager: FileManager
    ) -> String? {
        guard let directory = stagingDirectory(
            baseDirectory: baseDirectory,
            directoryName: directoryName,
            itemId: itemId,
            fileManager: fileManager
        ) else { return nil }
        let fileURL = directory.appendingPathComponent(filename, isDirectory: false)
        guard fileURL.deletingLastPathComponent().path == directory.path else { return nil }
        guard writeDataNoFollow(data, to: fileURL, fileManager: fileManager) else { return nil }
        return "\(directoryName)/\(itemId.uuidString)/\(filename)"
    }

    static func copyStagedFile(
        from sourceURL: URL,
        filename: String,
        itemId: UUID,
        baseDirectory: URL,
        directoryName: String,
        fileManager: FileManager
    ) -> String? {
        guard let directory = stagingDirectory(
            baseDirectory: baseDirectory,
            directoryName: directoryName,
            itemId: itemId,
            fileManager: fileManager
        ) else { return nil }
        let destinationURL = directory.appendingPathComponent(filename, isDirectory: false)
        guard destinationURL.deletingLastPathComponent().path == directory.path else { return nil }
        guard copyFileNoFollow(from: sourceURL, to: destinationURL, fileManager: fileManager) else { return nil }
        return "\(directoryName)/\(itemId.uuidString)/\(filename)"
    }

    private static func createAndValidateDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        if fileManager.fileExists(atPath: url.path) {
            return isRealDirectory(url)
        }
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
            return isRealDirectory(url)
        } catch {
            return false
        }
    }

    private static func isRealDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
            return false
        }
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    private static func writeDataNoFollow(_ data: Data, to destinationURL: URL, fileManager: FileManager) -> Bool {
        let descriptor = open(
            destinationURL.path,
            O_CREAT | O_EXCL | O_NOFOLLOW | O_WRONLY,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else { return false }
        var shouldRemovePartialFile = true
        defer {
            close(descriptor)
            if shouldRemovePartialFile {
                try? fileManager.removeItem(at: destinationURL)
            }
        }
        guard writeAll(data, to: descriptor) else { return false }
        shouldRemovePartialFile = false
        return true
    }

    private static func copyFileNoFollow(from sourceURL: URL, to destinationURL: URL, fileManager: FileManager) -> Bool {
        let descriptor = open(
            destinationURL.path,
            O_CREAT | O_EXCL | O_NOFOLLOW | O_WRONLY,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else { return false }
        var shouldRemovePartialFile = true
        defer {
            close(descriptor)
            if shouldRemovePartialFile {
                try? fileManager.removeItem(at: destinationURL)
            }
        }
        guard let source = try? FileHandle(forReadingFrom: sourceURL) else { return false }
        defer { try? source.close() }
        while true {
            let chunk = source.readData(ofLength: 64 * 1024)
            if chunk.isEmpty { break }
            guard writeAll(chunk, to: descriptor) else { return false }
        }
        shouldRemovePartialFile = false
        return true
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) -> Bool {
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return true }
            var bytesRemaining = rawBuffer.count
            var offset = 0
            while bytesRemaining > 0 {
                let written = write(descriptor, baseAddress.advanced(by: offset), bytesRemaining)
                guard written > 0 else { return false }
                offset += written
                bytesRemaining -= written
            }
            return true
        }
    }
}
