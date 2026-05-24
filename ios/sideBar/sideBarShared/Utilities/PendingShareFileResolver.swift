import Foundation

struct PendingShareFileResolver {
    let baseDirectory: URL
    let directoryName: String
    let fileManager: FileManager

    func resolve(relativePath: String) -> URL? {
        guard let components = pathComponents(for: relativePath) else { return nil }
        let root = pathStandardizedURL(baseDirectory.appendingPathComponent(directoryName, isDirectory: true))
        guard isDirectory(root), isSymlink(root) == false else { return nil }

        let directory = root.appendingPathComponent(components.uuid, isDirectory: true)
        guard isDirectory(directory), isSymlink(directory) == false else { return nil }

        let candidate = pathStandardizedURL(directory.appendingPathComponent(components.filename, isDirectory: false))
        guard candidate.path.hasPrefix(root.path + "/") else { return nil }
        guard isSymlink(candidate) == false else { return nil }
        return candidate
    }

    func itemDirectory(for fileURL: URL, relativePath: String) -> URL? {
        guard let components = pathComponents(for: relativePath) else { return nil }
        let root = pathStandardizedURL(baseDirectory.appendingPathComponent(directoryName, isDirectory: true))
        let directory = pathStandardizedURL(fileURL.deletingLastPathComponent())
        guard directory.deletingLastPathComponent().path == root.path else { return nil }
        guard directory.lastPathComponent == components.uuid else { return nil }
        guard isDirectory(directory), isSymlink(directory) == false else { return nil }
        return directory
    }

    func emptyItemDirectories(olderThan cutoff: Date) -> [URL] {
        let root = pathStandardizedURL(baseDirectory.appendingPathComponent(directoryName, isDirectory: true))
        guard isDirectory(root), isSymlink(root) == false else { return [] }
        guard let directories = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return directories.compactMap { emptyItemDirectory(for: $0, root: root, olderThan: cutoff) }
    }

    private func emptyItemDirectory(for url: URL, root: URL, olderThan cutoff: Date) -> URL? {
        guard let values = try? url.resourceValues(forKeys: [.creationDateKey, .isDirectoryKey, .isSymbolicLinkKey]),
              values.isSymbolicLink != true,
              values.isDirectory == true,
              let createdAt = values.creationDate,
              createdAt < cutoff else { return nil }
        let directory = pathStandardizedURL(url)
        guard directory.deletingLastPathComponent().path == root.path else { return nil }
        guard UUID(uuidString: directory.lastPathComponent) != nil else { return nil }
        guard (try? fileManager.contentsOfDirectory(atPath: directory.path).isEmpty) == true else {
            return nil
        }
        return directory
    }

    private func pathComponents(for relativePath: String) -> (uuid: String, filename: String)? {
        guard relativePath.hasPrefix("\(directoryName)/") else { return nil }
        guard relativePath.first != "/" else { return nil }
        let parts = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else { return nil }
        guard parts[0] == directoryName else { return nil }
        guard UUID(uuidString: parts[1]) != nil else { return nil }
        guard !parts[2].isEmpty else { return nil }
        guard parts.allSatisfy({ $0 != "." && $0 != ".." }) else { return nil }
        return (parts[1], parts[2])
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private func pathStandardizedURL(_ url: URL) -> URL {
        url.standardizedFileURL
    }
}
