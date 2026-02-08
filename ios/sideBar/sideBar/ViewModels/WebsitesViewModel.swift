import Foundation
import sideBarShared
import Combine
import OSLog

// MARK: - WebsitesViewModel

@MainActor
/// Manages saved websites list, detail views, and website saving functionality.
///
/// This ViewModel coordinates website operations including:
/// - Loading and displaying the saved websites list
/// - Website detail view with full content
/// - Saving new websites via URL with validation
/// - Pin, archive, rename, and delete operations
/// - Pending website state for optimistic UI updates
/// - Real-time event handling for live sync
///
/// ## URL Validation
/// Uses `WebsiteURLValidator` to normalize and validate URLs before saving.
/// Blocks localhost, direct IPs, and invalid TLDs.
///
/// ## Optimistic Updates
/// When saving a website, a `PendingWebsiteItem` is created immediately for
/// responsive UI, then replaced with the actual item once the server responds.
///
/// ## Threading
/// Marked `@MainActor` - all properties and methods execute on the main thread.
///
/// ## Usage
/// ```swift
/// let viewModel = WebsitesViewModel(
///     api: websitesAPI,
///     store: websitesStore,
///     toastCenter: toastCenter,
///     networkStatus: connectivityMonitor
/// )
/// await viewModel.load()
/// let success = await viewModel.saveWebsite(url: "https://example.com")
/// await viewModel.selectWebsite(id: websiteId)
/// ```
public final class WebsitesViewModel: ObservableObject {
    /// Holds a pending website captured from an extension flow.
    public struct PendingWebsiteItem: Identifiable, Equatable {
        public let id: String
        public let title: String
        public let domain: String
        public let url: String
    }

    @Published public internal(set) var items: [WebsiteItem] = []
    @Published public internal(set) var active: WebsiteDetail?
    @Published public internal(set) var selectedWebsiteId: String?
    @Published public internal(set) var isLoading: Bool = false
    @Published public internal(set) var isLoadingDetail: Bool = false
    @Published public internal(set) var isLoadingArchived: Bool = false
    @Published public var panelSearchQuery: String = ""
    @Published public internal(set) var errorMessage: String?
    @Published public internal(set) var isSavingWebsite: Bool = false
    @Published public internal(set) var saveErrorMessage: String?
    @Published public internal(set) var pendingWebsite: PendingWebsiteItem?
    @Published public internal(set) var archivedSummary: ArchivedSummary?
    @Published public internal(set) var panelFilteredItems: [WebsiteItem] = []
    @Published public internal(set) var panelPinnedItemsSorted: [WebsiteItem] = []
    @Published public internal(set) var panelMainItems: [WebsiteItem] = []
    @Published public internal(set) var panelArchivedItems: [WebsiteItem] = []
    @Published public internal(set) var panelNavigationWebsiteIds: [String] = []
    var detailLoadingMessage: String {
        pendingWebsite?.title ?? "Reading..."
    }

    let api: any WebsitesProviding
    let store: WebsitesStore
    let ingestionStore: IngestionStore?
    let toastCenter: ToastCenter
    let networkStatus: any NetworkStatusProviding
    let transcriptPollIntervalNanoseconds: UInt64
    let logger = Logger(subsystem: "sideBar", category: "WebsitesViewModel")
    @Published var inFlightTranscriptRequests: [String: Set<String>] = [:]
    var pendingTranscriptJobs: [String: Set<String>] = [:]
    var transcriptPollingTasks: [String: Task<Void, Never>] = [:]
    var cancellables = Set<AnyCancellable>()

    public init(
        api: any WebsitesProviding,
        store: WebsitesStore,
        ingestionStore: IngestionStore? = nil,
        toastCenter: ToastCenter,
        networkStatus: any NetworkStatusProviding,
        transcriptPollInterval: TimeInterval = 5
    ) {
        self.api = api
        self.store = store
        self.ingestionStore = ingestionStore
        self.toastCenter = toastCenter
        self.networkStatus = networkStatus
        self.transcriptPollIntervalNanoseconds = UInt64(
            max(transcriptPollInterval, 0.25) * 1_000_000_000
        )

        store.$items
            .sink { [weak self] items in
                self?.items = items
                self?.clearPendingIfNeeded(items: items)
                self?.updatePanelDerivedState()
            }
            .store(in: &cancellables)

        store.$active
            .sink { [weak self] active in
                self?.active = active
                self?.syncTranscriptPolling(for: active)
            }
            .store(in: &cancellables)

        store.$archivedSummary
            .sink { [weak self] summary in
                self?.archivedSummary = summary
            }
            .store(in: &cancellables)

        ingestionStore?.$items
            .sink { [weak self] items in
                self?.pendingTranscriptJobs = Self.pendingTranscriptMap(from: items)
            }
            .store(in: &cancellables)

        $panelSearchQuery
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.updatePanelDerivedState()
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

    public func loadArchived(force: Bool = false) async {
        guard !isLoadingArchived else { return }
        isLoadingArchived = true
        defer { isLoadingArchived = false }
        await store.loadArchivedList(force: force)
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
        guard let trimmed = url.trimmedOrNil else {
            saveErrorMessage = "Enter a valid URL."
            return false
        }
        guard let normalized = WebsiteURLValidator.normalizedCandidate(trimmed) else {
            saveErrorMessage = "Enter a valid URL."
            return false
        }
        if networkStatus.isOffline {
            if PendingShareStore.shared.enqueueWebsite(url: normalized.absoluteString) != nil {
                pendingWebsite = makePendingWebsite(from: normalized)
                saveErrorMessage = nil
                toastCenter.show(message: "Saved for later", style: .success)
                return true
            }
            saveErrorMessage = "Could not save for later."
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
                    faviconUrl: detail?.faviconUrl,
                    faviconR2Key: detail?.faviconR2Key,
                    youtubeTranscripts: detail?.youtubeTranscripts,
                    readingTime: detail?.readingTime,
                    updatedAt: detail?.updatedAt,
                    lastOpenedAt: detail?.lastOpenedAt,
                    deletedAt: nil
                ),
                persist: true
            )
            pendingWebsite = nil
            store.invalidateList()
            Task { [weak self] in
                do {
                    try await self?.store.loadList(force: true)
                } catch {
                    self?.logger.error("Failed to refresh websites list after save: \(error.localizedDescription, privacy: .public)")
                }
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
        if networkStatus.isOffline {
            do {
                try await store.enqueuePin(id: id, pinned: pinned)
            } catch WriteQueueError.queueFull {
                errorMessage = "Sync queue full. Review pending changes."
            } catch {
                errorMessage = "Failed to queue website update"
            }
            return
        }
        do {
            let updated = try await api.pin(
                id: id,
                pinned: pinned,
                clientUpdatedAt: store.currentUpdatedAt(id: id)
            )
            store.updateListItem(updated, persist: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func renameWebsite(id: String, title: String) async {
        guard let trimmed = title.trimmedOrNil else {
            return
        }
        errorMessage = nil
        if networkStatus.isOffline {
            do {
                try await store.enqueueRename(id: id, title: trimmed)
            } catch WriteQueueError.queueFull {
                errorMessage = "Sync queue full. Review pending changes."
            } catch {
                errorMessage = "Failed to queue website update"
            }
            return
        }
        do {
            let updated = try await api.rename(
                id: id,
                title: trimmed,
                clientUpdatedAt: store.currentUpdatedAt(id: id)
            )
            store.updateListItem(updated, persist: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func setArchived(id: String, archived: Bool) async {
        errorMessage = nil
        if networkStatus.isOffline {
            do {
                try await store.enqueueArchive(id: id, archived: archived)
                if archived, selectedWebsiteId == id {
                    clearSelection()
                }
            } catch WriteQueueError.queueFull {
                errorMessage = "Sync queue full. Review pending changes."
            } catch {
                errorMessage = "Failed to queue website update"
            }
            return
        }
        do {
            let updated = try await api.archive(
                id: id,
                archived: archived,
                clientUpdatedAt: store.currentUpdatedAt(id: id)
            )
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
        if networkStatus.isOffline {
            do {
                try await store.enqueueDelete(id: id)
                if selectedWebsiteId == id {
                    clearSelection()
                }
            } catch WriteQueueError.queueFull {
                errorMessage = "Sync queue full. Review pending changes."
            } catch {
                errorMessage = "Failed to queue website update"
            }
            return
        }
        let attemptedUpdatedAt = store.currentUpdatedAt(id: id)
        do {
            try await api.delete(id: id, clientUpdatedAt: attemptedUpdatedAt)
            store.removeItem(id: id, persist: true)
            if selectedWebsiteId == id {
                clearSelection()
            }
        } catch {
            if isDeleteConflict(error),
               await retryDeleteAfterRefresh(id: id, fallbackUpdatedAt: attemptedUpdatedAt) {
                return
            }
            toastCenter.show(message: "Failed to delete website")
        }
    }

    public func requestYouTubeTranscript(websiteId: String, url: String) async {
        guard networkStatus.isOffline == false else {
            errorMessage = "Transcript requires an online connection."
            return
        }
        guard let videoId = YouTubeURLPolicy.extractVideoId(from: url) else {
            errorMessage = "Invalid YouTube URL."
            return
        }
        if isTranscriptPending(websiteId: websiteId, videoId: videoId) {
            return
        }
        setTranscriptRequestInFlight(true, websiteId: websiteId, videoId: videoId)
        defer {
            setTranscriptRequestInFlight(false, websiteId: websiteId, videoId: videoId)
        }

        do {
            let response = try await api.transcribeYouTube(id: websiteId, url: url)
            if let detail = response.readyWebsite {
                store.applyTranscriptReadyDetail(detail)
                stopTranscriptPolling(websiteId: websiteId, videoId: videoId)
                return
            }

            store.applyTranscriptQueuedUpdate(
                websiteId: websiteId,
                videoId: videoId,
                status: response.queuedStatus ?? "queued",
                fileId: response.queuedFileId
            )
            startTranscriptPollingIfNeeded(websiteId: websiteId, videoId: videoId)
        } catch {
            errorMessage = ErrorMapping.message(for: error)
        }
    }

    public func isTranscriptPending(websiteId: String, videoId: String) -> Bool {
        let normalizedVideoId = videoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedVideoId.isEmpty else { return false }
        if let status = active?.youtubeTranscripts?[normalizedVideoId]?.status?.lowercased() {
            if Self.isTranscriptStatusPending(status) {
                return true
            }
            if status == "ready" || status == "failed" || status == "canceled" {
                return false
            }
        }
        if inFlightTranscriptRequests[websiteId]?.contains(normalizedVideoId) == true {
            return true
        }
        return pendingTranscriptJobs[websiteId]?.contains(normalizedVideoId) == true
    }

    public func applyRealtimeEvent(_ payload: RealtimePayload<WebsiteRealtimeRecord>) async {
        let websiteId = payload.record?.id ?? payload.oldRecord?.id
        if payload.eventType == .delete, selectedWebsiteId == websiteId {
            selectedWebsiteId = nil
        }
        store.applyRealtimeEvent(payload)
    }

}
