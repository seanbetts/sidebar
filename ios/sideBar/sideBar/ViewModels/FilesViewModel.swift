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
    private let temporaryStore: TemporaryFileStore
    private let store: FilesStore
    private var cancellables = Set<AnyCancellable>()

    public init(api: any FilesProviding, store: FilesStore, temporaryStore: TemporaryFileStore) {
        self.api = api
        self.temporaryStore = temporaryStore
        self.store = store

        store.$tree
            .sink { [weak self] tree in
                self?.tree = tree
            }
            .store(in: &cancellables)

        store.$activeFile
            .sink { [weak self] file in
                self?.activeFile = file
            }
            .store(in: &cancellables)
    }

    public func loadTree(basePath: String = "documents") async {
        errorMessage = nil
        do {
            try await store.loadTree(basePath: basePath)
        } catch {
            if tree == nil {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func loadContent(basePath: String = "documents", path: String) async {
        errorMessage = nil
        do {
            try await store.loadContent(basePath: basePath, path: path)
        } catch {
            if activeFile == nil {
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
                    spreadsheet: nil,
                    youtubeEmbedURL: nil
                )
            default:
                let data = try await api.download(basePath: basePath, path: path)
                let fileURL = try temporaryStore.store(data: data, filename: name)
                viewerState = FileViewerState(
                    title: name,
                    kind: kind,
                    text: nil,
                    fileURL: fileURL,
                    spreadsheet: nil,
                    youtubeEmbedURL: nil
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    public func clearSelection() {
        selectedPath = nil
        viewerState = nil
        store.clearActiveFile()
    }
}
