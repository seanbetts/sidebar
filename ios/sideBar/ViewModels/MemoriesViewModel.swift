import Foundation
import Combine

@MainActor
public final class MemoriesViewModel: ObservableObject {
    @Published public private(set) var items: [MemoryItem] = []
    @Published public private(set) var errorMessage: String? = nil

    private let api: MemoriesAPI

    public init(api: MemoriesAPI) {
        self.api = api
    }

    public func load() async {
        errorMessage = nil
        do {
            items = try await api.list()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
