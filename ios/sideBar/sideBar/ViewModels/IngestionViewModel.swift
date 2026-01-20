import Foundation
import Combine
import UniformTypeIdentifiers

// TODO: Revisit to prefer native-first data sources where applicable.

@MainActor
/// Coordinates ingestion list state and polling for files.
public final class IngestionViewModel: ObservableObject {
    @Published public private(set) var items: [IngestionListItem] = []
    @Published public private(set) var activeMeta: IngestionMetaResponse? = nil
    @Published public private(set) var selectedFileId: String? = nil
    @Published public private(set) var selectedDerivativeKind: String? = nil
    @Published public private(set) var viewerState: FileViewerState? = nil
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var isLoadingContent: Bool = false
    @Published public private(set) var isSelecting: Bool = false
    @Published public private(set) var isOffline: Bool = false
    @Published public private(set) var errorMessage: String? = nil
    @Published public private(set) var isIngestingYouTube: Bool = false
    @Published public private(set) var readyFileNotification: ReadyFileNotification? = nil
    @Published public private(set) var lastReadyMessage: ReadyFileNotification? = nil

    private let api: any IngestionProviding
    private let temporaryStore: TemporaryFileStore
    private let store: IngestionStore
    private let uploadManager: IngestionUploadManaging
    private var cancellables = Set<AnyCancellable>()
    private var securityScopedURLs: [String: URL] = [:]
    private var jobPollingTasks: [String: Task<Void, Never>] = [:]
    private var listPollingTask: PollingTask? = nil
    private var statusCache: [String: String] = [:]
    private let readyMessageTask = ManagedTask()

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
