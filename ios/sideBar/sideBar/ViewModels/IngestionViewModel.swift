import Foundation
import Combine
import UniformTypeIdentifiers

// TODO: Revisit to prefer native-first data sources where applicable.

@MainActor
/// Coordinates ingestion list state and polling for files.
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
