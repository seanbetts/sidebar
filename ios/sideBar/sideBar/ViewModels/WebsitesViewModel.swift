import Foundation
import Combine

// TODO: Revisit to prefer native-first data sources where applicable.

@MainActor
public final class WebsitesViewModel: ObservableObject {
    @Published public private(set) var items: [WebsiteItem] = []
    @Published public private(set) var active: WebsiteDetail? = nil
    @Published public private(set) var selectedWebsiteId: String? = nil
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var isLoadingDetail: Bool = false
    @Published public private(set) var errorMessage: String? = nil

    private let api: any WebsitesProviding
    private let store: WebsitesStore
    private var cancellables = Set<AnyCancellable>()

    public init(api: any WebsitesProviding, store: WebsitesStore) {
        self.api = api
        self.store = store

        store.$items
            .sink { [weak self] items in
                self?.items = items
            }
            .store(in: &cancellables)

        store.$active
            .sink { [weak self] active in
                self?.active = active
            }
            .store(in: &cancellables)
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        do {
            try await store.loadList()
        } catch {
            if items.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    public func loadById(id: String) async {
        errorMessage = nil
        selectedWebsiteId = id
        isLoadingDetail = true
        do {
            try await store.loadDetail(id: id)
        } catch {
            if active == nil {
                errorMessage = error.localizedDescription
            }
        }
        isLoadingDetail = false
    }

    public func selectWebsite(id: String) async {
        await loadById(id: id)
    }

    public func clearSelection() {
        selectedWebsiteId = nil
        store.clearActive()
    }

    public func setPinned(id: String, pinned: Bool) async {
        errorMessage = nil
        do {
            let updated = try await api.pin(id: id, pinned: pinned)
            store.updateListItem(updated)
            store.invalidateList()
            store.invalidateDetail(id: id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func applyRealtimeEvent(_ payload: RealtimePayload<WebsiteRealtimeRecord>) async {
        let websiteId = payload.record?.id ?? payload.oldRecord?.id
        store.invalidateList()
        if let websiteId {
            store.invalidateDetail(id: websiteId)
        }

        switch payload.eventType {
        case .delete:
            if let websiteId {
                store.removeItem(id: websiteId)
                if selectedWebsiteId == websiteId {
                    selectedWebsiteId = nil
                }
            }
        case .insert, .update:
            if let record = payload.record, let mapped = RealtimeMappers.mapWebsite(record) {
                store.updateListItem(mapped)
                if selectedWebsiteId == mapped.id {
                    await loadById(id: mapped.id)
                }
            } else {
                await load()
            }
        }
    }
}
