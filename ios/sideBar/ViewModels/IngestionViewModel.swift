import Foundation
import Combine

@MainActor
public final class IngestionViewModel: ObservableObject {
    @Published public private(set) var items: [IngestionListItem] = []
    @Published public private(set) var activeMeta: IngestionMetaResponse? = nil
    @Published public private(set) var errorMessage: String? = nil

    private let api: IngestionAPI

    public init(api: IngestionAPI) {
        self.api = api
    }

    public func load() async {
        errorMessage = nil
        do {
            let response = try await api.list()
            items = response.items
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func loadMeta(fileId: String) async {
        errorMessage = nil
        do {
            activeMeta = try await api.getMeta(fileId: fileId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
