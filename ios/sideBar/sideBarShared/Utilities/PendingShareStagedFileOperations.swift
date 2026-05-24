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
}
