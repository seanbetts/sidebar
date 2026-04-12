import Foundation
import Combine
import UniformTypeIdentifiers
import sideBarShared

// MARK: - IngestionViewModel

private final class IngestionViewModelTeardownBag {
    private let lock = NSLock()
    private var jobPollingTasks: [String: Task<Void, Never>] = [:]
    private var listPollingTask: PollingTask?

    func setJobPollingTasks(_ tasks: [String: Task<Void, Never>]) {
        lock.lock()
        jobPollingTasks = tasks
        lock.unlock()
    }

    func setListPollingTask(_ task: PollingTask?) {
        lock.lock()
        listPollingTask = task
        lock.unlock()
    }

    deinit {
        lock.lock()
        let jobPollingTasks = jobPollingTasks
        let listPollingTask = listPollingTask
        lock.unlock()

        for task in jobPollingTasks.values { task.cancel() }
        listPollingTask?.cancel()
    }
}

@MainActor
/// Manages file ingestion, upload tracking, and file viewer state.
///
/// This ViewModel handles the complete file ingestion lifecycle:
/// - File selection and upload initiation
/// - Upload progress tracking via `IngestionUploadManaging`
/// - Job status polling for processing state
/// - File content viewing with derivative support
/// - YouTube URL ingestion
/// - Real-time notifications for ready files
///
/// ## Architecture
/// The ViewModel is split across multiple files for maintainability:
/// - `IngestionViewModel.swift`: Core state and initialization
/// - `IngestionViewModel+Public.swift`: Public API methods
/// - `IngestionViewModel+Private.swift`: Internal helpers and polling logic
/// - `IngestionViewModelTypes.swift`: Supporting types and enums
///
/// ## Upload Flow
/// 1. User selects files via document picker
/// 2. Files are copied to temporary storage with security-scoped access
/// 3. Upload manager handles chunked uploads with progress
/// 4. Job polling tracks server-side processing
/// 5. Ready notifications appear when processing completes
///
/// ## Threading
/// Marked `@MainActor` - all properties and methods execute on the main thread.
/// Background polling uses `PollingTask` for automatic lifecycle management.
///
/// ## Usage
/// ```swift
/// let viewModel = IngestionViewModel(api: ingestionAPI, store: store, toastCenter: toast, ...)
/// await viewModel.load()
/// await viewModel.ingestFiles(urls: selectedURLs)
/// await viewModel.selectFile(id: fileId)
/// ```
public final class IngestionViewModel: ObservableObject {
    public typealias JobPollingSleep = @Sendable (UInt64) async throws -> Void

    @Published public var items: [IngestionListItem] = []
    @Published public var panelSearchQuery: String = ""
    @Published public private(set) var itemsVersion: Int = 0
    @Published public internal(set) var panelFilteredItems: [IngestionListItem] = []
    @Published public internal(set) var panelSearchResults: [IngestionListItem] = []
    @Published public internal(set) var panelPinnedItems: [IngestionListItem] = []
    @Published public internal(set) var panelCategorizedItems: [String: [IngestionListItem]] = [:]
    @Published public internal(set) var panelCategoriesWithItems: [String] = []
    @Published public internal(set) var panelNavigationFileIds: [String] = []
    @Published public var activeMeta: IngestionMetaResponse?
    @Published public var selectedFileId: String?
    @Published public var selectedDerivativeKind: String?
    @Published public var viewerState: FileViewerState?
    @Published public var isLoading: Bool = false
    @Published public var isLoadingContent: Bool = false
    @Published public var isSelecting: Bool = false
    @Published public var isOffline: Bool = false
    @Published public var errorMessage: String?
    @Published public var isIngestingYouTube: Bool = false
    @Published public var readyFileNotification: ReadyFileNotification?
    @Published public var latestHeaderReadyEvent: ReadyFileNotification?
    @Published public var lastReadyMessage: ReadyFileNotification?

    let api: any IngestionProviding
    let temporaryStore: TemporaryFileStore
    let store: IngestionStore
    let toastCenter: ToastCenter
    let pendingShareStore: PendingShareStore
    let uploadManager: IngestionUploadManaging
    let ingestionProgressActivityCoordinator: IngestionProgressActivityCoordinator
    let networkStatus: (any NetworkStatusProviding)?
    let jobPollingBaseInterval: TimeInterval
    let jobPollingMaxInterval: TimeInterval
    let jobPollingMaxConsecutiveFailures: Int
    let jobPollingJitterWindow: TimeInterval
    let jobPollingSleep: JobPollingSleep
    var cancellables = Set<AnyCancellable>()
    var securityScopedURLs: [String: URL] = [:]
    var jobPollingTasks: [String: Task<Void, Never>] = [:] {
        didSet {
            teardownBag.setJobPollingTasks(jobPollingTasks)
        }
    }
    var jobPollingTaskTokens: [String: UUID] = [:]
    var listPollingTask: PollingTask? {
        didSet {
            teardownBag.setListPollingTask(listPollingTask)
        }
    }
    var isListPollRequestInFlight = false
    var listPollingConsecutiveFailures = 0
    var nextListPollAttemptAt: Date?
    var statusCache: [String: String] = [:]
    let ingestionProgressActivityTask = ManagedTask()
    private let teardownBag = IngestionViewModelTeardownBag()

    public convenience init(
        api: any IngestionProviding,
        store: IngestionStore,
        temporaryStore: TemporaryFileStore,
        uploadManager: IngestionUploadManaging,
        toastCenter: ToastCenter,
        pendingShareStore: PendingShareStore = .shared,
        networkStatus: (any NetworkStatusProviding)? = nil,
        jobPollingBaseInterval: TimeInterval = 2,
        jobPollingMaxInterval: TimeInterval = 20,
        jobPollingMaxConsecutiveFailures: Int = 6,
        jobPollingJitterWindow: TimeInterval = 0.4,
        jobPollingSleep: @escaping JobPollingSleep = { nanoseconds in
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.init(
            api: api,
            store: store,
            temporaryStore: temporaryStore,
            uploadManager: uploadManager,
            toastCenter: toastCenter,
            ingestionProgressActivityCoordinator: IngestionProgressActivityCoordinator(),
            pendingShareStore: pendingShareStore,
            networkStatus: networkStatus,
            jobPollingBaseInterval: jobPollingBaseInterval,
            jobPollingMaxInterval: jobPollingMaxInterval,
            jobPollingMaxConsecutiveFailures: jobPollingMaxConsecutiveFailures,
            jobPollingJitterWindow: jobPollingJitterWindow,
            jobPollingSleep: jobPollingSleep
        )
    }

    init(
        api: any IngestionProviding,
        store: IngestionStore,
        temporaryStore: TemporaryFileStore,
        uploadManager: IngestionUploadManaging,
        toastCenter: ToastCenter,
        ingestionProgressActivityCoordinator: IngestionProgressActivityCoordinator,
        pendingShareStore: PendingShareStore = .shared,
        networkStatus: (any NetworkStatusProviding)? = nil,
        jobPollingBaseInterval: TimeInterval = 2,
        jobPollingMaxInterval: TimeInterval = 20,
        jobPollingMaxConsecutiveFailures: Int = 6,
        jobPollingJitterWindow: TimeInterval = 0.4,
        jobPollingSleep: @escaping JobPollingSleep = { nanoseconds in
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.api = api
        self.temporaryStore = temporaryStore
        self.store = store
        self.toastCenter = toastCenter
        self.pendingShareStore = pendingShareStore
        self.uploadManager = uploadManager
        self.ingestionProgressActivityCoordinator = ingestionProgressActivityCoordinator
        self.networkStatus = networkStatus
        self.jobPollingBaseInterval = max(jobPollingBaseInterval, 0.1)
        self.jobPollingMaxInterval = max(jobPollingMaxInterval, self.jobPollingBaseInterval)
        self.jobPollingMaxConsecutiveFailures = max(1, jobPollingMaxConsecutiveFailures)
        self.jobPollingJitterWindow = max(0, jobPollingJitterWindow)
        self.jobPollingSleep = jobPollingSleep

        store.$items
            .sink { [weak self] items in
                self?.items = items
                self?.updateListPollingState(items: items)
                self?.detectReadyTransitions(items: items)
                self?.itemsVersion &+= 1
                self?.updatePanelDerivedState()
                self?.ingestionProgressActivityTask.run { [weak self] in
                    await self?.syncIngestionProgressActivities(items: items)
                }
            }
            .store(in: &cancellables)

        store.$activeMeta
            .sink { [weak self] meta in
                self?.activeMeta = meta
            }
            .store(in: &cancellables)

        store.$isOffline
            .sink { [weak self] isOffline in
                self?.isOffline = isOffline
            }
            .store(in: &cancellables)

        $panelSearchQuery
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.updatePanelDerivedState()
            }
            .store(in: &cancellables)
    }
}
