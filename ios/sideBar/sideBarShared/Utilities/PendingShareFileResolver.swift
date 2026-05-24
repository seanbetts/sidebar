import Foundation

struct PendingShareFileResolver {
    let baseDirectory: URL
    let directoryName: String
    let fileManager: FileManager

    func resolve(relativePath: String) -> URL? {
        guard relativePath.hasPrefix("\(directoryName)/") else { return nil }
        guard relativePath.first != "/" else { return nil }

        let parts = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else { return nil }
        guard parts[0] == directoryName else { return nil }
        guard UUID(uuidString: parts[1]) != nil else { return nil }
        guard !parts[2].isEmpty else { return nil }
        guard parts.allSatisfy({ $0 != "." && $0 != ".." }) else { return nil }

        let root = standardizedDirectoryURL(baseDirectory.appendingPathComponent(directoryName, isDirectory: true))
        let candidate = standardizedFileURL(baseDirectory.appendingPathComponent(relativePath, isDirectory: false))
        guard candidate.path.hasPrefix(root.path + "/") else { return nil }
        return candidate
    }

    func itemDirectory(for fileURL: URL) -> URL? {
        let root = standardizedDirectoryURL(baseDirectory.appendingPathComponent(directoryName, isDirectory: true))
        let directory = standardizedDirectoryURL(fileURL.deletingLastPathComponent())
        guard directory.deletingLastPathComponent().path == root.path else { return nil }
        return directory
    }

    private func standardizedDirectoryURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private func standardizedFileURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}
