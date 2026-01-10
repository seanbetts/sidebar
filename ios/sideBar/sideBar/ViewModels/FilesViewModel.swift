import Foundation
import Combine

// TODO: Revisit to prefer native-first data sources where applicable.

@MainActor
public final class FilesViewModel: ObservableObject {
    @Published public private(set) var tree: FileTree? = nil
    @Published public private(set) var activeFile: FileContent? = nil
    @Published public private(set) var selectedPath: String? = nil
    @Published public private(set) var viewerState: FileViewerState? = nil
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var errorMessage: String? = nil

    private let api: any FilesProviding
    private let cache: CacheClient
    private let temporaryStore: TemporaryFileStore

    public init(api: any FilesProviding, cache: CacheClient, temporaryStore: TemporaryFileStore) {
        self.api = api
        self.cache = cache
        self.temporaryStore = temporaryStore
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

    public func selectFile(basePath: String = "documents", path: String, name: String) async {
        selectedPath = path
        viewerState = nil
        isLoading = true
        errorMessage = nil
        let kind = FileViewerKind.infer(path: path, mimeType: nil, derivativeKind: nil)
        do {
            switch kind {
            case .markdown, .text, .json, .spreadsheet:
                await loadContent(basePath: basePath, path: path)
                guard let response = activeFile else { break }
                let fileURL = try temporaryStore.store(text: response.content, filename: name)
                viewerState = FileViewerState(
                    title: name,
                    kind: kind == .spreadsheet ? .text : kind,
                    text: response.content,
                    fileURL: fileURL,
                    spreadsheet: nil
                )
            default:
                let data = try await api.download(basePath: basePath, path: path)
                let fileURL = try temporaryStore.store(data: data, filename: name)
                viewerState = FileViewerState(
                    title: name,
                    kind: kind,
                    text: nil,
                    fileURL: fileURL,
                    spreadsheet: nil
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
