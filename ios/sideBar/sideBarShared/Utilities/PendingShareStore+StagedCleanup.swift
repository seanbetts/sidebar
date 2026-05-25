import Foundation

extension PendingShareStore {
    func stagedCleanupResults(for items: [PendingShareItem]) -> PendingShareStagedCleanupResults {
        var results = PendingShareStagedCleanupResults()
        var resultsByStagedReference: [String: PendingShareStagedCleanupResult] = [:]
        for item in items {
            guard let stagedReference = stagedCleanupReference(for: item) else {
                results.succeeded.insert(item.id)
                continue
            }
            let result: PendingShareStagedCleanupResult
            if let existingResult = resultsByStagedReference[stagedReference] {
                result = existingResult
            } else {
                result = removeStagedFileIfPresent(for: item)
                resultsByStagedReference[stagedReference] = result
            }
            switch result {
            case .succeeded:
                results.succeeded.insert(item.id)
            case .invalidMetadata:
                results.droppedInvalid.insert(item.id)
            case .failed:
                results.failed.append(item)
            }
        }
        return results
    }

    func removeStagedFileIfPresent(for item: PendingShareItem) -> PendingShareStagedCleanupResult {
        guard item.kind == .file || item.kind == .image else { return .succeeded }
        guard let relativePath = item.filePath else { return .succeeded }
        guard let baseDirectory = rootDirectory else { return .failed }
        var didRun = false
        var cleanupResult = PendingShareStagedCleanupResult.failed
        let didSucceed = stagedFileMutationLock(baseDirectory) { [self] in
            didRun = true
            let resolver = self.makeFileResolver(baseDirectory: baseDirectory)
            guard let fileURL = resolver.resolve(relativePath: relativePath) else {
                cleanupResult = .invalidMetadata
                return true
            }
            guard removeStagedFile(at: fileURL) else { return false }
            guard removeItemDirectoryIfEmpty(for: fileURL, relativePath: relativePath, resolver: resolver) else {
                return false
            }
            cleanupResult = .succeeded
            return true
        }
        return didRun && didSucceed ? cleanupResult : .failed
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

enum PendingShareStagedCleanupResult {
    case succeeded
    case invalidMetadata
    case failed
}

struct PendingShareStagedCleanupResults {
    var succeeded = Set<UUID>()
    var droppedInvalid = Set<UUID>()
    var failed: [PendingShareItem] = []
}
