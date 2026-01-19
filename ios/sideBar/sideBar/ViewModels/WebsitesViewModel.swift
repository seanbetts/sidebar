import Foundation
import Combine

// TODO: Revisit to prefer native-first data sources where applicable.

@MainActor
public final class WebsitesViewModel: ObservableObject {
    public struct PendingWebsiteItem: Identifiable, Equatable {
        public let id: String
        public let title: String
        public let domain: String
        public let url: String
    }

    @Published public private(set) var items: [WebsiteItem] = []
    @Published public private(set) var active: WebsiteDetail? = nil
    @Published public private(set) var selectedWebsiteId: String? = nil
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var isLoadingDetail: Bool = false
    @Published public private(set) var errorMessage: String? = nil
    @Published public private(set) var isSavingWebsite: Bool = false
    @Published public private(set) var saveErrorMessage: String? = nil
    @Published public private(set) var pendingWebsite: PendingWebsiteItem? = nil

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

    public func load(force: Bool = false) async {
        if items.isEmpty {
            isLoading = true
        }
        errorMessage = nil
        do {
            try await store.loadList(force: force)
        } catch {
            if items.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    public func refreshFromExtension() async {
        errorMessage = nil
        do {
            try await store.loadList(force: true)
        } catch {
            if items.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func showPendingFromExtension(url: String) {
        guard let normalized = WebsiteURLValidator.normalizedCandidate(url) else {
            return
        }
        pendingWebsite = makePendingWebsite(from: normalized)
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
        let previousSelectedId = selectedWebsiteId
        let pending = makePendingWebsite(from: normalized)
        pendingWebsite = pending
        selectedWebsiteId = pending.id
        saveErrorMessage = nil
        isSavingWebsite = true
        isLoadingDetail = true
        defer {
            isSavingWebsite = false
            isLoadingDetail = false
        }
        do {
            let response = try await api.save(url: normalized.absoluteString)
            guard response.success, let data = response.data else {
                pendingWebsite = nil
                selectedWebsiteId = previousSelectedId
                saveErrorMessage = "Failed to save website"
                return false
            }
            selectedWebsiteId = data.id
            try await store.loadDetail(id: data.id, force: true)
            let detail = active
            store.insertItemAtTop(
                WebsiteItem(
                    id: data.id,
                    title: detail?.title ?? data.title,
                    url: detail?.url ?? data.url,
                    domain: detail?.domain ?? data.domain,
                    savedAt: detail?.savedAt,
                    publishedAt: detail?.publishedAt,
                    pinned: detail?.pinned ?? false,
                    pinnedOrder: detail?.pinnedOrder,
                    archived: detail?.archived ?? false,
                    youtubeTranscripts: detail?.youtubeTranscripts,
                    updatedAt: detail?.updatedAt,
                    lastOpenedAt: detail?.lastOpenedAt
                ),
                persist: true
            )
            pendingWebsite = nil
            store.invalidateList()
            Task { [weak self] in
                try? await self?.store.loadList(force: true)
            }
            return true
        } catch {
            pendingWebsite = nil
            selectedWebsiteId = previousSelectedId
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

    public func renameWebsite(id: String, title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        errorMessage = nil
        do {
            let updated = try await api.rename(id: id, title: trimmed)
            store.updateListItem(updated, persist: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func setArchived(id: String, archived: Bool) async {
        errorMessage = nil
        do {
            let updated = try await api.archive(id: id, archived: archived)
            store.updateListItem(updated, persist: true)
            if archived, selectedWebsiteId == id {
                clearSelection()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func deleteWebsite(id: String) async {
        errorMessage = nil
        do {
            try await api.delete(id: id)
            store.removeItem(id: id, persist: true)
            if selectedWebsiteId == id {
                clearSelection()
            }
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

    private func makePendingWebsite(from url: URL) -> PendingWebsiteItem {
        let host = url.host ?? url.absoluteString
        let domain = host.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
        return PendingWebsiteItem(
            id: "pending-\(UUID().uuidString)",
            title: "Reading...",
            domain: domain,
            url: url.absoluteString
        )
    }
}
