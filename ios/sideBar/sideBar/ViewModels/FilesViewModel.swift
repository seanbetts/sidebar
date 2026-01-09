import Foundation
import Combine

// TODO: Revisit to prefer native-first data sources where applicable.

@MainActor
public final class FilesViewModel: ObservableObject {
    @Published public private(set) var tree: FileTree? = nil
    @Published public private(set) var activeFile: FileContent? = nil
    @Published public private(set) var errorMessage: String? = nil

    private let api: any FilesProviding
    private let cache: CacheClient

    public init(api: any FilesProviding, cache: CacheClient) {
        self.api = api
        self.cache = cache
    }

    public func loadTree(basePath: String = "documents") async {
        errorMessage = nil
        let cacheKey = CacheKeys.filesTree(basePath: basePath)
        let cached: FileTree? = cache.get(key: cacheKey)
        if let cached {
            tree = cached
        }
        do {
            let response = try await api.listTree(basePath: basePath)
            tree = response
            cache.set(key: cacheKey, value: response, ttlSeconds: CachePolicy.filesTree)
        } catch {
            if cached == nil {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func loadContent(basePath: String = "documents", path: String) async {
        errorMessage = nil
        let cacheKey = CacheKeys.fileContent(basePath: basePath, path: path)
        let cached: FileContent? = cache.get(key: cacheKey)
        if let cached {
            activeFile = cached
        }
        do {
            let response = try await api.getContent(basePath: basePath, path: path)
            activeFile = response
            cache.set(key: cacheKey, value: response, ttlSeconds: CachePolicy.fileContent)
        } catch {
            if cached == nil {
                errorMessage = error.localizedDescription
            }
        }
    }
}
