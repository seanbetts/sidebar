import Foundation
import Combine

@MainActor
public final class FilesStore: ObservableObject {
    @Published public private(set) var tree: FileTree? = nil
    @Published public private(set) var activeFile: FileContent? = nil

    private let api: any FilesProviding
    private let cache: CacheClient
    private var isRefreshingTree = false

    public init(api: any FilesProviding, cache: CacheClient) {
        self.api = api
        self.cache = cache
    }

    public func loadTree(basePath: String, force: Bool = false) async throws {
        let cacheKey = CacheKeys.filesTree(basePath: basePath)
        let cached: FileTree? = force ? nil : cache.get(key: cacheKey)
        if let cached {
            applyTreeUpdate(cached, persist: false, cacheKey: cacheKey)
            Task { [weak self] in
                await self?.refreshTree(basePath: basePath, cacheKey: cacheKey)
            }
            return
        }
        let response = try await api.listTree(basePath: basePath)
        applyTreeUpdate(response, persist: true, cacheKey: cacheKey)
    }

    public func loadContent(basePath: String, path: String, force: Bool = false) async throws {
        let cacheKey = CacheKeys.fileContent(basePath: basePath, path: path)
        if !force, let cached: FileContent = cache.get(key: cacheKey) {
            applyContentUpdate(cached, persist: false, cacheKey: cacheKey)
            return
        }
        let response = try await api.getContent(basePath: basePath, path: path)
        applyContentUpdate(response, persist: true, cacheKey: cacheKey)
    }

    public func clearActiveFile() {
        activeFile = nil
    }

    public func reset() {
        tree = nil
        activeFile = nil
    }

    private func refreshTree(basePath: String, cacheKey: String) async {
        guard !isRefreshingTree else {
            return
        }
        isRefreshingTree = true
        defer { isRefreshingTree = false }
        do {
            let response = try await api.listTree(basePath: basePath)
            applyTreeUpdate(response, persist: true, cacheKey: cacheKey)
        } catch {
            // Ignore background refresh failures; cache remains source of truth.
        }
    }

    private func applyTreeUpdate(_ incoming: FileTree, persist: Bool, cacheKey: String) {
        guard shouldUpdateTree(incoming) else {
            return
        }
        tree = incoming
        if persist {
            cache.set(key: cacheKey, value: incoming, ttlSeconds: CachePolicy.filesTree)
        }
    }

    private func shouldUpdateTree(_ incoming: FileTree) -> Bool {
        guard let current = tree else {
            return true
        }
        return FileTreeSignature.make(current) != FileTreeSignature.make(incoming)
    }

    private func applyContentUpdate(_ incoming: FileContent, persist: Bool, cacheKey: String) {
        guard shouldUpdateContent(incoming) else {
            return
        }
        activeFile = incoming
        if persist {
            cache.set(key: cacheKey, value: incoming, ttlSeconds: CachePolicy.fileContent)
        }
    }

    private func shouldUpdateContent(_ incoming: FileContent) -> Bool {
        guard let current = activeFile else {
            return true
        }
        return current.modified != incoming.modified || current.content != incoming.content
    }
}
