import Foundation
import sideBarShared
import Combine

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

    @Published public private(set) var items: [WebsiteItem] = []
    @Published public private(set) var active: WebsiteDetail?
    @Published public private(set) var selectedWebsiteId: String?
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var isLoadingDetail: Bool = false
    @Published public private(set) var isLoadingArchived: Bool = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isSavingWebsite: Bool = false
    @Published public private(set) var saveErrorMessage: String?
    @Published public private(set) var pendingWebsite: PendingWebsiteItem?
    @Published public private(set) var archivedSummary: ArchivedSummary?

    private let api: any WebsitesProviding
    private let store: WebsitesStore
    private let ingestionStore: IngestionStore?
    private let toastCenter: ToastCenter
    private let networkStatus: any NetworkStatusProviding
    private let transcriptPollIntervalNanoseconds: UInt64
    private var pendingTranscriptJobs: [String: Set<String>] = [:]
    private var transcriptPollingTasks: [String: Task<Void, Never>] = [:]
    private var cancellables = Set<AnyCancellable>()

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
        do {
            try await api.delete(id: id, clientUpdatedAt: store.currentUpdatedAt(id: id))
            store.removeItem(id: id, persist: true)
            if selectedWebsiteId == id {
                clearSelection()
            }
        } catch {
            errorMessage = error.localizedDescription
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
        return pendingTranscriptJobs[websiteId]?.contains(normalizedVideoId) == true
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

    private func clearPendingIfNeeded(items: [WebsiteItem]) {
        guard let pendingWebsite else { return }
        let pendingUrl = pendingWebsite.url
        if items.contains(where: { $0.url == pendingUrl }) {
            self.pendingWebsite = nil
        }
    }

    private func syncTranscriptPolling(for active: WebsiteDetail?) {
        guard let active else {
            stopTranscriptPolling()
            return
        }
        var activeKeys = Set<String>()
        for (videoId, entry) in active.youtubeTranscripts ?? [:] {
            guard Self.isTranscriptStatusPending(entry.status) else { continue }
            activeKeys.insert(Self.transcriptPollingKey(websiteId: active.id, videoId: videoId))
            startTranscriptPollingIfNeeded(websiteId: active.id, videoId: videoId)
        }
        for key in Array(transcriptPollingTasks.keys) where !activeKeys.contains(key) {
            stopTranscriptPolling(key: key)
        }
    }

    private func startTranscriptPollingIfNeeded(websiteId: String, videoId: String) {
        let key = Self.transcriptPollingKey(websiteId: websiteId, videoId: videoId)
        guard transcriptPollingTasks[key] == nil else { return }
        transcriptPollingTasks[key] = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: self?.transcriptPollIntervalNanoseconds ?? 0)
                } catch {
                    return
                }
                guard let self else { return }
                guard self.selectedWebsiteId == websiteId else {
                    self.stopTranscriptPolling(key: key)
                    return
                }
                guard self.networkStatus.isOffline == false else {
                    continue
                }
                do {
                    try await self.store.loadDetail(id: websiteId, force: true)
                } catch {
                    continue
                }
                guard let current = self.active, current.id == websiteId else {
                    continue
                }
                guard let status = current.youtubeTranscripts?[videoId]?.status?.lowercased() else {
                    self.stopTranscriptPolling(key: key)
                    return
                }
                if Self.isTranscriptStatusPending(status) {
                    continue
                }
                if status == "failed" || status == "canceled" {
                    self.errorMessage = current.youtubeTranscripts?[videoId]?.error ?? "Transcript failed."
                }
                self.stopTranscriptPolling(key: key)
                return
            }
        }
    }

    private func stopTranscriptPolling(
        websiteId: String? = nil,
        videoId: String? = nil,
        key: String? = nil
    ) {
        if let key {
            transcriptPollingTasks[key]?.cancel()
            transcriptPollingTasks[key] = nil
            return
        }
        if let websiteId, let videoId {
            let entryKey = Self.transcriptPollingKey(websiteId: websiteId, videoId: videoId)
            transcriptPollingTasks[entryKey]?.cancel()
            transcriptPollingTasks[entryKey] = nil
            return
        }
        for task in transcriptPollingTasks.values {
            task.cancel()
        }
        transcriptPollingTasks = [:]
    }

    private static func transcriptPollingKey(websiteId: String, videoId: String) -> String {
        "\(websiteId):\(videoId)"
    }

    private static func isTranscriptStatusPending(_ status: String?) -> Bool {
        guard let status else { return false }
        switch status.lowercased() {
        case "queued", "processing", "retrying":
            return true
        default:
            return false
        }
    }

    private static func pendingTranscriptMap(from items: [IngestionListItem]) -> [String: Set<String>] {
        let pendingStatuses = Set(["queued", "processing", "retrying"])
        var map: [String: Set<String>] = [:]
        for item in items {
            guard let status = item.job.status?.lowercased(),
                  pendingStatuses.contains(status),
                  let metadata = item.file.sourceMetadata,
                  metadataBool(metadata, key: "website_transcript") == true,
                  let websiteId = metadataString(metadata, key: "website_id"),
                  let videoId = metadataString(metadata, key: "video_id") else {
                continue
            }
            map[websiteId, default: []].insert(videoId)
        }
        return map
    }

    private static func metadataString(_ metadata: [String: AnyCodable], key: String) -> String? {
        guard let value = metadata[key]?.value else { return nil }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func metadataBool(_ metadata: [String: AnyCodable], key: String) -> Bool? {
        guard let value = metadata[key]?.value else { return nil }
        if let boolValue = value as? Bool {
            return boolValue
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let string = value as? String {
            switch string.lowercased() {
            case "true", "1":
                return true
            case "false", "0":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    /// Refreshes widget data by fetching the latest websites list
    /// Called by background refresh task to keep widgets up-to-date
    func refreshWidgetData() async {
        do {
            try await store.loadList(force: true)
        } catch {
            // Silently fail - widget will use cached data
        }
    }
}
