import Foundation
import Combine
import UniformTypeIdentifiers

// MARK: - IngestionViewModel

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
/// let viewModel = IngestionViewModel(api: ingestionAPI, store: store, ...)
/// await viewModel.load()
/// await viewModel.ingestFiles(urls: selectedURLs)
/// await viewModel.selectFile(id: fileId)
/// ```
public final class IngestionViewModel: ObservableObject {
    @Published public var items: [IngestionListItem] = []
    @Published public var activeMeta: IngestionMetaResponse? = nil
    @Published public var selectedFileId: String? = nil
    @Published public var selectedDerivativeKind: String? = nil
    @Published public var viewerState: FileViewerState? = nil
    @Published public var isLoading: Bool = false
    @Published public var isLoadingContent: Bool = false
    @Published public var isSelecting: Bool = false
    @Published public var isOffline: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var isIngestingYouTube: Bool = false
    @Published public var readyFileNotification: ReadyFileNotification? = nil
    @Published public var lastReadyMessage: ReadyFileNotification? = nil

    let api: any IngestionProviding
    let temporaryStore: TemporaryFileStore
    let store: IngestionStore
    let uploadManager: IngestionUploadManaging
    var cancellables = Set<AnyCancellable>()
    var securityScopedURLs: [String: URL] = [:]
    var jobPollingTasks: [String: Task<Void, Never>] = [:]
    var listPollingTask: PollingTask? = nil
    var statusCache: [String: String] = [:]
    let readyMessageTask = ManagedTask()

    public init(
        api: any IngestionProviding,
        store: IngestionStore,
        temporaryStore: TemporaryFileStore,
        uploadManager: IngestionUploadManaging
    ) {
        self.api = api
        self.temporaryStore = temporaryStore
        self.store = store
        self.uploadManager = uploadManager

        store.$items
            .sink { [weak self] items in
                self?.items = items
                self?.updateListPollingState(items: items)
                self?.detectReadyTransitions(items: items)
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
    }
}
