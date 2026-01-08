import Foundation
import Combine

@MainActor
public final class FilesViewModel: ObservableObject {
    @Published public private(set) var tree: FileTree? = nil
    @Published public private(set) var activeFile: FileContent? = nil
    @Published public private(set) var errorMessage: String? = nil

    private let api: FilesAPI

    public init(api: FilesAPI) {
        self.api = api
    }

    public func loadTree(basePath: String = "documents") async {
        errorMessage = nil
        do {
            tree = try await api.listTree(basePath: basePath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func loadContent(basePath: String = "documents", path: String) async {
        errorMessage = nil
        do {
            activeFile = try await api.getContent(basePath: basePath, path: path)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
