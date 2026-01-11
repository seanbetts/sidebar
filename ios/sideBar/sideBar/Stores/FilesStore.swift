import Foundation

@MainActor
public final class FilesStore: ObservableObject {
    @Published public private(set) var tree: FileTree? = nil
    @Published public private(set) var activeFile: FileContent? = nil

    private let api: any FilesProviding
    private let cache: CacheClient

    public init(api: any FilesProviding, cache: CacheClient) {
        self.api = api
        self.cache = cache
    }

    public func loadTree(basePath: String, force: Bool = false) async throws {
        let cacheKey = CacheKeys.filesTree(basePath: basePath)
        if !force, let cached: FileTree = cache.get(key: cacheKey) {
            tree = cached
            return
        }
        let response = try await api.listTree(basePath: basePath)
        tree = response
        cache.set(key: cacheKey, value: response, ttlSeconds: CachePolicy.filesTree)
    }

    public func loadContent(basePath: String, path: String, force: Bool = false) async throws {
        let cacheKey = CacheKeys.fileContent(basePath: basePath, path: path)
        if !force, let cached: FileContent = cache.get(key: cacheKey) {
            activeFile = cached
            return
        }
        let response = try await api.getContent(basePath: basePath, path: path)
        activeFile = response
        cache.set(key: cacheKey, value: response, ttlSeconds: CachePolicy.fileContent)
    }

    public func clearActiveFile() {
        activeFile = nil
    }

    public func reset() {
        tree = nil
        activeFile = nil
    }
}
