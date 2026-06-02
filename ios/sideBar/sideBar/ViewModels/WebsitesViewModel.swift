import Foundation
import sideBarShared
import Combine
import OSLog

// MARK: - WebsitesViewModel

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
@MainActor public final class WebsitesViewModel: ObservableObject {
    typealias PollingSleep = @Sendable (UInt64) async throws -> Void

    @Published public internal(set) var items: [WebsiteItem] = []
    @Published public internal(set) var active: WebsiteDetail?
    @Published public internal(set) var selectedWebsiteId: String?
    @Published public internal(set) var isLoading: Bool = false
    @Published public internal(set) var listLoadState: ContentListLoadState = .idle
    @Published public internal(set) var isLoadingDetail: Bool = false
    @Published public internal(set) var isLoadingArchived: Bool = false
    var lastForcedLoadAt: Date?
    private let minForcedLoadInterval: TimeInterval = 30
    @Published public var panelSearchQuery: String = ""
    @Published public internal(set) var errorMessage: String?
    @Published public internal(set) var isSavingWebsite: Bool = false
    @Published public internal(set) var saveErrorMessage: String?
    @Published public internal(set) var pendingWebsites: [PendingWebsiteItem] = []
    @Published public internal(set) var archivedSummary: ArchivedSummary?
    @Published public internal(set) var panelFilteredItems: [WebsiteItem] = []
    @Published public internal(set) var panelPinnedItemsSorted: [WebsiteItem] = []
    @Published public internal(set) var panelMainItems: [WebsiteItem] = []
    @Published public internal(set) var panelArchivedItems: [WebsiteItem] = []
    @Published public internal(set) var panelNavigationWebsiteIds: [String] = []
    let api: any WebsitesProviding
    let store: WebsitesStore
    let ingestionStore: IngestionStore?
    let toastCenter: ToastCenter
    let networkStatus: any NetworkStatusProviding
    let jobProgressCoordinator: AsyncJobProgressCoordinator
    let transcriptPollIntervalNanoseconds: UInt64
    let transcriptPollMaxIntervalNanoseconds: UInt64
    let transcriptPollMaxConsecutiveFailures: Int
    let transcriptPollJitterWindowNanoseconds: UInt64
    let jobPollingSleep: PollingSleep
    let transcriptPollingSleep: PollingSleep
    let logger = Logger(subsystem: "sideBar", category: "WebsitesViewModel")
    @Published var inFlightTranscriptRequests: [String: Set<String>] = [:]
    var pendingTranscriptJobs: [String: Set<String>] = [:]
    var transcriptPollingTasks: [String: Task<Void, Never>] = [:] {
        didSet {
            teardownBag.setTranscriptPollingTasks(transcriptPollingTasks)
        }
    }
    var jobPollingTasks: [String: Task<Void, Never>] = [:] {
        didSet {
            teardownBag.setJobPollingTasks(jobPollingTasks)
        }
    }
    var jobPollingTaskTokens: [String: UUID] = [:]
    var allowsFallbackPolling: @MainActor (AppSection, Bool) -> Bool = { _, _ in true }
    var onJobTerminalState: @MainActor (DomainSyncChange) async -> Void = { _ in }
    var cancellables = Set<AnyCancellable>()
    private let teardownBag = WebsitesViewModelTeardownBag()

    public convenience init(
        api: any WebsitesProviding,
        store: WebsitesStore,
        ingestionStore: IngestionStore? = nil,
        toastCenter: ToastCenter,
        networkStatus: any NetworkStatusProviding,
        transcriptPollInterval: TimeInterval = 5,
        transcriptPollMaxInterval: TimeInterval = 20,
        transcriptPollMaxConsecutiveFailures: Int = 6,
        transcriptPollJitterWindow: TimeInterval = 0.4,
        transcriptPollMinimumInterval: TimeInterval = 0.25
    ) {
        self.init(
            api: api,
            store: store,
            ingestionStore: ingestionStore,
            toastCenter: toastCenter,
            networkStatus: networkStatus,
            jobProgressCoordinator: AsyncJobProgressCoordinator(),
            transcriptPollInterval: transcriptPollInterval,
            transcriptPollMaxInterval: transcriptPollMaxInterval,
            transcriptPollMaxConsecutiveFailures: transcriptPollMaxConsecutiveFailures,
            transcriptPollJitterWindow: transcriptPollJitterWindow,
            transcriptPollMinimumInterval: transcriptPollMinimumInterval
        )
    }

    init(
        api: any WebsitesProviding,
        store: WebsitesStore,
        ingestionStore: IngestionStore? = nil,
        toastCenter: ToastCenter,
        networkStatus: any NetworkStatusProviding,
        jobProgressCoordinator: AsyncJobProgressCoordinator,
        transcriptPollInterval: TimeInterval = 5,
        transcriptPollMaxInterval: TimeInterval = 20,
        transcriptPollMaxConsecutiveFailures: Int = 6,
        transcriptPollJitterWindow: TimeInterval = 0.4,
        transcriptPollMinimumInterval: TimeInterval = 0.25,
        jobPollingSleep: @escaping PollingSleep = { nanoseconds in
            try await Task.sleep(nanoseconds: nanoseconds)
        },
        transcriptPollingSleep: @escaping PollingSleep = { nanoseconds in
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.api = api
        self.store = store
        self.ingestionStore = ingestionStore
        self.toastCenter = toastCenter
        self.networkStatus = networkStatus
        self.jobProgressCoordinator = jobProgressCoordinator
        self.jobPollingSleep = jobPollingSleep
        self.transcriptPollingSleep = transcriptPollingSleep
        let minimumPollInterval = max(transcriptPollMinimumInterval, 0)
        let clampedPollInterval = max(transcriptPollInterval, minimumPollInterval)
        self.transcriptPollIntervalNanoseconds = UInt64(clampedPollInterval * 1_000_000_000)
        self.transcriptPollMaxIntervalNanoseconds = UInt64(
            max(transcriptPollMaxInterval, clampedPollInterval) * 1_000_000_000
        )
        self.transcriptPollMaxConsecutiveFailures = max(1, transcriptPollMaxConsecutiveFailures)
        self.transcriptPollJitterWindowNanoseconds = UInt64(
            max(transcriptPollJitterWindow, 0) * 1_000_000_000
        )

        store.$items
            .sink { [weak self] items in
                self?.items = items
                self?.updatePanelDerivedState()
            }
            .store(in: &cancellables)

        store.$active
            .sink { [weak self] active in
                WebsiteQueueDebugTrace.log(
                    "websites-detail.active.changed",
                    details: [
                        "active_id=\(active?.id ?? "nil")"
                    ]
                )
                self?.active = active
                self?.syncTranscriptProgress(for: active)
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

    public func loadArchived(force: Bool = false) async {
        guard !isLoadingArchived else { return }
        isLoadingArchived = true
        defer { isLoadingArchived = false }
        await store.loadArchivedList(force: force)
    }

    public func loadById(id: String, force: Bool = false) async {
        let start = ProcessInfo.processInfo.systemUptime
        WebsiteQueueDebugTrace.log(
            "websites-detail.load.request",
            details: [
                "requested_id=\(id)",
                "selected_before=\(selectedWebsiteId ?? "nil")",
                "active_before=\(active?.id ?? "nil")",
                "has_cached_detail=\(store.hasCachedDetail(id: id))"
            ]
        )
        errorMessage = nil
        if active?.id != id {
            store.clearActive()
        }
        selectedWebsiteId = id
        if !networkStatus.offlineCapabilityPolicy.canAttemptServerRead,
           !store.hasCachedDetail(id: id) {
            isLoadingDetail = false
            errorMessage = "This website isn't available offline yet."
            return
        }
        isLoadingDetail = true
        do {
            try await store.loadDetail(id: id, force: force)
            let elapsedMs = Int((ProcessInfo.processInfo.systemUptime - start) * 1000)
            WebsiteQueueDebugTrace.log(
                "websites-detail.load.success",
                details: [
                    "requested_id=\(id)",
                    "active_after=\(active?.id ?? "nil")",
                    "elapsed_ms=\(elapsedMs)"
                ]
            )
        } catch {
            if active == nil {
                errorMessage = ErrorMapping.message(for: error)
            }
            let elapsedMs = Int((ProcessInfo.processInfo.systemUptime - start) * 1000)
            WebsiteQueueDebugTrace.log(
                "websites-detail.load.failure",
                details: [
                    "requested_id=\(id)",
                    "elapsed_ms=\(elapsedMs)",
                    "error=\(ErrorMapping.message(for: error))"
                ]
            )
        }
        isLoadingDetail = false
    }

    public func selectWebsite(id: String) async {
        WebsiteQueueDebugTrace.log(
            "websites-detail.select",
            details: [
                "requested_id=\(id)",
                "selected_before=\(selectedWebsiteId ?? "nil")"
            ]
        )
        await loadById(id: id)
    }

    public func clearSelection() {
        selectedWebsiteId = nil
        store.clearActive()
    }

    public func saveWebsite(url: String, selectAfterSave: Bool = true) async -> Bool {
        guard let normalized = normalizedWebsiteURL(from: url) else { return false }
        if networkStatus.offlineCapabilityPolicy.shouldQueueWrites {
            return enqueueOfflineWebsiteSave(
                for: normalized,
                selectAfterSave: selectAfterSave
            )
        }

        if !selectAfterSave {
            do {
                return try await saveWebsiteWithoutSelection(normalizedURL: normalized)
            } catch is CancellationError {
                return false
            } catch {
                return false
            }
        }
        let previousSelectedId = beginWebsiteSave(for: normalized)
        do {
            let response = try await api.save(url: normalized.absoluteString)
            updatePendingWebsiteJobId(response.jobId, for: normalized)
            registerWebsiteSaveJob(
                jobId: response.jobId,
                pendingURL: normalized
            )
            startWebsiteJobPollingIfAllowed(
                jobId: response.jobId,
                pendingURL: normalized,
                previousSelectedId: previousSelectedId,
                shouldSelectOnCompletion: true
            )
            return true
        } catch {
            endWebsiteSave()
            failWebsiteSave(
                previousSelectedId: previousSelectedId,
                pendingURL: normalized,
                message: ErrorMapping.message(for: error)
            )
            return false
        }
    }

    func continuePendingWebsiteJobsInBackground(maxDuration: TimeInterval = 25) async -> Bool {
        guard allowsFallbackPolling(.websites, true) else {
            return false
        }
        let deadline = Date().addingTimeInterval(max(1, maxDuration))

        do {
            while Date() < deadline {
                try Task.checkCancellation()
                guard allowsFallbackPolling(.websites, true) else {
                    return false
                }
                let pendingJobs = pendingWebsites.compactMap { pending -> PendingWebsiteItem? in
                    pending.jobId != nil ? pending : nil
                }
                guard !pendingJobs.isEmpty else { return true }

                for pending in pendingJobs {
                    try Task.checkCancellation()
                    guard let jobId = pending.jobId,
                          let pendingURL = URL(string: pending.url) else {
                        continue
                    }
                    let shouldSelectOnCompletion = pending.source == .directSave
                    let isTerminal = await refreshWebsiteJobStatus(
                        jobId: jobId,
                        pendingURL: pendingURL,
                        previousSelectedId: pending.selectionFallbackId,
                        shouldSelectOnCompletion: shouldSelectOnCompletion
                    )
                    if isTerminal {
                        continue
                    }
                }

                if pendingWebsites.contains(where: { $0.jobId != nil }) == false {
                    return true
                }

                try await Task.sleep(for: .seconds(3))
            }
        } catch is CancellationError {
            return false
        } catch {
            return false
        }

        return pendingWebsites.contains(where: { $0.jobId != nil }) == false
    }

    func saveQueuedWebsite(url: String) async throws -> Bool {
        guard let normalized = normalizedWebsiteURL(from: url) else { return false }
        return try await saveWebsiteWithoutSelection(normalizedURL: normalized)
    }

    private func saveWebsiteWithoutSelection(normalizedURL: URL) async throws -> Bool {
        _ = upsertPendingWebsite(
            from: normalizedURL,
            source: .queuedShare,
            status: .queued
        )
        saveErrorMessage = nil
        do {
            let response = try await api.save(url: normalizedURL.absoluteString)
            updatePendingWebsiteJobId(response.jobId, for: normalizedURL)
            registerWebsiteSaveJob(
                jobId: response.jobId,
                pendingURL: normalizedURL
            )
            startWebsiteJobPollingIfAllowed(
                jobId: response.jobId,
                pendingURL: normalizedURL,
                previousSelectedId: nil,
                shouldSelectOnCompletion: false
            )
            return true
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            updatePendingWebsiteStatus(for: normalizedURL.absoluteString, status: .failed)
            saveErrorMessage = ErrorMapping.message(for: error)
            return false
        }
    }

    public func setPinned(id: String, pinned: Bool) async {
        errorMessage = nil
        do {
            try await store.enqueuePin(id: id, pinned: pinned)
            errorMessage = nil
        } catch WriteQueueError.queueFull {
            errorMessage = "Sync queue full. Review pending changes."
        } catch {
            errorMessage = "Failed to queue website update"
        }
    }

    public func renameWebsite(id: String, title: String) async {
        guard let trimmed = title.trimmedOrNil else {
            return
        }
        errorMessage = nil
        do {
            try await store.enqueueRename(id: id, title: trimmed)
            errorMessage = nil
        } catch WriteQueueError.queueFull {
            errorMessage = "Sync queue full. Review pending changes."
        } catch {
            errorMessage = "Failed to queue website update"
        }
    }

    public func setArchived(id: String, archived: Bool) async {
        errorMessage = nil
        do {
            try await store.enqueueArchive(id: id, archived: archived)
            if shouldClearSelectionAfterArchiving(id: id, archived: archived) {
                clearSelection()
            }
            errorMessage = nil
        } catch WriteQueueError.queueFull {
            errorMessage = "Sync queue full. Review pending changes."
        } catch {
            errorMessage = "Failed to queue website update"
        }
    }

    private func shouldClearSelectionAfterArchiving(id: String, archived: Bool) -> Bool {
        guard archived else { return false }
        return selectedWebsiteId == id || active?.id == id
    }

    public func deleteWebsite(id: String) async {
        errorMessage = nil
        do {
            try await store.enqueueDelete(id: id)
            if selectedWebsiteId == id {
                clearSelection()
            }
            errorMessage = nil
        } catch WriteQueueError.queueFull {
            errorMessage = "Sync queue full. Review pending changes."
        } catch {
            errorMessage = "Failed to queue website update"
        }
    }

}

extension WebsitesViewModel {
    public func load(force: Bool = false) async {
        var effectiveForce = force
        if force {
            let now = Date()
            if let last = lastForcedLoadAt, now.timeIntervalSince(last) < minForcedLoadInterval {
                effectiveForce = false
            } else {
                lastForcedLoadAt = now
            }
        }
        if items.isEmpty {
            isLoading = true
        }
        ContentListReadRecovery.begin(hasVisibleContent: !items.isEmpty)
            .apply(errorMessage: &errorMessage, loadState: &listLoadState)
        do {
            try await store.loadList(force: effectiveForce)
            ContentListReadRecovery.success()
                .apply(errorMessage: &errorMessage, loadState: &listLoadState)
        } catch {
            if let failureTransition = ContentListReadRecovery.failure(
                error: error,
                hasVisibleContent: !items.isEmpty
            ) {
                failureTransition.apply(errorMessage: &errorMessage, loadState: &listLoadState)
            }
        }
        isLoading = false
    }
}
