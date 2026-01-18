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
    @Published public private(set) var isSavingWebsite: Bool = false
    @Published public private(set) var saveErrorMessage: String? = nil

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

    public func saveWebsite(url: String) async -> Bool {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            saveErrorMessage = "Enter a valid URL."
            return false
        }
        guard let normalized = WebsiteURLValidator.normalizedCandidate(trimmed) else {
            saveErrorMessage = "Enter a valid URL."
            return false
        }
        saveErrorMessage = nil
        isSavingWebsite = true
        defer { isSavingWebsite = false }
        do {
            let response = try await api.save(url: normalized.absoluteString)
            guard response.success, let data = response.data else {
                saveErrorMessage = "Failed to save website"
                return false
            }
            store.invalidateList()
            selectedWebsiteId = data.id
            try await store.loadDetail(id: data.id, force: true)
            Task { [weak self] in
                try? await self?.store.loadList(force: true)
            }
            return true
        } catch {
            saveErrorMessage = ErrorMapping.message(for: error)
            return false
        }
    }

    public func setPinned(id: String, pinned: Bool) async {
        errorMessage = nil
        do {
            let updated = try await api.pin(id: id, pinned: pinned)
            store.updateListItem(updated, persist: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func applyRealtimeEvent(_ payload: RealtimePayload<WebsiteRealtimeRecord>) async {
        let websiteId = payload.record?.id ?? payload.oldRecord?.id
        if payload.eventType == .delete, selectedWebsiteId == websiteId {
            selectedWebsiteId = nil
        }
        store.applyRealtimeEvent(payload)
    }
}
