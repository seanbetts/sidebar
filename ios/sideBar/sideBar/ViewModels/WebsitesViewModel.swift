import Foundation
import Combine

// TODO: Revisit to prefer native-first data sources where applicable.

@MainActor
public final class WebsitesViewModel: ObservableObject {
    @Published public private(set) var items: [WebsiteItem] = []
    @Published public private(set) var active: WebsiteDetail? = nil
    @Published public private(set) var errorMessage: String? = nil

    private let api: WebsitesAPI

    public init(api: WebsitesAPI) {
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

    public func loadById(id: String) async {
        errorMessage = nil
        do {
            active = try await api.get(id: id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
