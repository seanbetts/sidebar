import Foundation

extension PendingShareStore {
    func stagedCleanupResults(for items: [PendingShareItem]) -> (succeeded: Set<UUID>, failed: [PendingShareItem]) {
        var succeeded = Set<UUID>()
        var failed: [PendingShareItem] = []
        var resultsByStagedReference: [String: Bool] = [:]
        for item in items {
            guard let stagedReference = stagedCleanupReference(for: item) else {
                succeeded.insert(item.id)
                continue
            }
            let didSucceed: Bool
            if let existingResult = resultsByStagedReference[stagedReference] {
                didSucceed = existingResult
            } else {
                didSucceed = removeStagedFileIfPresent(for: item)
                resultsByStagedReference[stagedReference] = didSucceed
            }
            if didSucceed {
                succeeded.insert(item.id)
            } else {
                failed.append(item)
            }
        }
        return (succeeded, failed)
    }

    func removeStagedFileIfPresent(for item: PendingShareItem) -> Bool {
        guard item.kind == .file || item.kind == .image else { return true }
        guard let relativePath = item.filePath else { return true }
        guard let baseDirectory = rootDirectory else { return false }
        var didRun = false
        let didSucceed = stagedFileMutationLock(baseDirectory) { [self] in
            didRun = true
            let resolver = self.makeFileResolver(baseDirectory: baseDirectory)
            guard let fileURL = resolver.resolve(relativePath: relativePath) else { return false }
            guard removeStagedFile(at: fileURL) else { return false }
            return removeItemDirectoryIfEmpty(for: fileURL, relativePath: relativePath, resolver: resolver)
        }
        return didRun && didSucceed
    }

    private func stagedCleanupReference(for item: PendingShareItem) -> String? {
        guard item.kind == .file || item.kind == .image else { return nil }
        return item.filePath
    }

    func cleanValidatedEmptyItemDirectories(olderThan cutoff: Date) -> Bool {
        guard let baseDirectory = rootDirectory else { return true }
        var didRun = false
        let didSucceed = stagedFileMutationLock(baseDirectory) { [self] in
            didRun = true
            let resolver = self.makeFileResolver(baseDirectory: baseDirectory)
            for directory in resolver.emptyItemDirectories(olderThan: cutoff) {
                do {
                    try self.fileManager.removeItem(at: directory)
                } catch {
                    if self.fileManager.fileExists(atPath: directory.path) {
                        return false
                    }
                }
            }
            return true
        }
        return didRun && didSucceed
    }

    private func removeStagedFile(at fileURL: URL) -> Bool {
        guard fileManager.fileExists(atPath: fileURL.path) else { return true }
        do {
            try fileManager.removeItem(at: fileURL)
        } catch {
            return fileManager.fileExists(atPath: fileURL.path) == false
        }
        return fileManager.fileExists(atPath: fileURL.path) == false
    }

    private func removeItemDirectoryIfEmpty(
        for fileURL: URL,
        relativePath: String,
        resolver: PendingShareFileResolver
    ) -> Bool {
        guard let directory = resolver.itemDirectory(for: fileURL, relativePath: relativePath) else { return true }
        guard let contents = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            return fileManager.fileExists(atPath: directory.path) == false
        }
        guard contents.isEmpty else { return true }
        do {
            try fileManager.removeItem(at: directory)
        } catch {
            guard fileManager.fileExists(atPath: directory.path) else { return true }
            return (try? fileManager.contentsOfDirectory(atPath: directory.path).isEmpty) == false
        }
        return true
    }
}
