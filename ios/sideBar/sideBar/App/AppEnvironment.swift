import Foundation
import Combine

@MainActor
public final class AppEnvironment: ObservableObject {
    public let container: ServiceContainer
    public var themeManager: ThemeManager
    public let chatStore: ChatStore
    public let notesStore: NotesStore
    public let websitesStore: WebsitesStore
    public let filesStore: FilesStore
    public let ingestionStore: IngestionStore
    public let tasksStore: TasksStore
    public let chatViewModel: ChatViewModel
    public let notesViewModel: NotesViewModel
    public let filesViewModel: FilesViewModel
    public let ingestionViewModel: IngestionViewModel
    public let websitesViewModel: WebsitesViewModel
    public let memoriesViewModel: MemoriesViewModel
    public let settingsViewModel: SettingsViewModel
    public let weatherViewModel: WeatherViewModel
    private let realtimeClient: RealtimeClient
    public let configError: EnvironmentConfigLoadError?
    private let networkMonitor: NetworkMonitor

    @Published public private(set) var isAuthenticated: Bool = false
    @Published public private(set) var isOffline: Bool = false
    @Published public var commandSelection: AppSection? = nil
    private var cancellables = Set<AnyCancellable>()

    public init(container: ServiceContainer, configError: EnvironmentConfigLoadError? = nil) {
        self.container = container
        self.themeManager = ThemeManager()
        self.chatStore = ChatStore(
            conversationsAPI: container.conversationsAPI,
            cache: container.cacheClient
        )
        self.notesStore = NotesStore(api: container.notesAPI, cache: container.cacheClient)
        self.websitesStore = WebsitesStore(api: container.websitesAPI, cache: container.cacheClient)
        self.filesStore = FilesStore(api: container.filesAPI, cache: container.cacheClient)
        self.ingestionStore = IngestionStore(api: container.ingestionAPI, cache: container.cacheClient)
        self.tasksStore = TasksStore()
        self.chatViewModel = ChatViewModel(
            chatAPI: container.chatAPI,
            conversationsAPI: container.conversationsAPI,
            cache: container.cacheClient,
            themeManager: themeManager,
            streamClient: container.makeChatStreamClient(handler: nil),
            chatStore: chatStore
        )
        let temporaryStore = TemporaryFileStore.shared
        self.notesViewModel = NotesViewModel(api: container.notesAPI, store: notesStore)
        self.filesViewModel = FilesViewModel(
            api: container.filesAPI,
            store: filesStore,
            temporaryStore: temporaryStore
        )
        self.ingestionViewModel = IngestionViewModel(
            api: container.ingestionAPI,
            store: ingestionStore,
            temporaryStore: temporaryStore
        )
        self.websitesViewModel = WebsitesViewModel(api: container.websitesAPI, store: websitesStore)
        self.memoriesViewModel = MemoriesViewModel(api: container.memoriesAPI, cache: container.cacheClient)
        self.settingsViewModel = SettingsViewModel(
            settingsAPI: container.settingsAPI,
            skillsAPI: container.skillsAPI,
            cache: container.cacheClient
        )
        self.weatherViewModel = WeatherViewModel(api: container.weatherAPI)
        self.realtimeClient = container.makeRealtimeClient(handler: nil)
        self.networkMonitor = NetworkMonitor()
        self.configError = configError
        self.isAuthenticated = container.authSession.accessToken != nil

        if let authAdapter = container.authSession as? SupabaseAuthAdapter {
            authAdapter.$accessToken
                .sink { [weak self] _token in
                    self?.refreshAuthState()
                }
                .store(in: &cancellables)
        }

        settingsViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        chatViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        notesViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        websitesViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        ingestionViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        weatherViewModel.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        networkMonitor.$isOffline
            .removeDuplicates()
            .sink { [weak self] isOffline in
                self?.isOffline = isOffline
                if isOffline == false {
                    self?.refreshOnReconnect()
                }
            }
            .store(in: &cancellables)

        if let realtimeClient = realtimeClient as? SupabaseRealtimeAdapter {
            realtimeClient.handler = self
        }
        realtimeClientStopStart()
        observeSelectionChanges()
    }

    public func refreshAuthState() {
        let wasAuthenticated = isAuthenticated
        isAuthenticated = container.authSession.accessToken != nil
        if wasAuthenticated && !isAuthenticated {
            container.cacheClient.clear()
            chatStore.reset()
            notesStore.reset()
            websitesStore.reset()
            filesStore.reset()
            ingestionStore.reset()
            tasksStore.reset()
            notesViewModel.clearSelection()
            websitesViewModel.clearSelection()
            filesViewModel.clearSelection()
            ingestionViewModel.clearSelection()
        }
        realtimeClientStopStart()
    }

    private func realtimeClientStopStart() {
        guard let userId = container.authSession.userId, isAuthenticated else {
            realtimeClient.stop()
            return
        }
        let token = container.authSession.accessToken
        Task {
            await realtimeClient.start(userId: userId, accessToken: token)
        }
    }

    private func observeSelectionChanges() {
        notesViewModel.$selectedNoteId
            .compactMap { $0 }
            .sink { [weak self] _ in
                self?.clearNonNoteSelections()
            }
            .store(in: &cancellables)

        websitesViewModel.$selectedWebsiteId
            .compactMap { $0 }
            .sink { [weak self] _ in
                self?.clearNonWebsiteSelections()
            }
            .store(in: &cancellables)

        ingestionViewModel.$selectedFileId
            .compactMap { $0 }
            .sink { [weak self] _ in
                self?.clearNonFileSelections()
            }
            .store(in: &cancellables)
    }

    private func clearNonNoteSelections() {
        websitesViewModel.clearSelection()
        ingestionViewModel.clearSelection()
        // TODO: Clear tasks selection once TasksViewModel exists.
    }

    private func clearNonWebsiteSelections() {
        notesViewModel.clearSelection()
        ingestionViewModel.clearSelection()
        // TODO: Clear tasks selection once TasksViewModel exists.
    }

    private func clearNonFileSelections() {
        notesViewModel.clearSelection()
        websitesViewModel.clearSelection()
        // TODO: Clear tasks selection once TasksViewModel exists.
    }

    private func refreshOnReconnect() {
        guard isAuthenticated else {
            return
        }
        Task {
            await chatViewModel.refreshConversations()
            await chatViewModel.refreshActiveConversation(silent: true)
            await notesViewModel.loadTree()
            await websitesViewModel.load()
            await ingestionViewModel.load()
        }
    }
}

extension AppEnvironment: RealtimeEventHandler {
    public func handleNoteEvent(_ payload: RealtimePayload<NoteRealtimeRecord>) {
        Task {
            await notesViewModel.applyRealtimeEvent(payload)
        }
    }

    public func handleWebsiteEvent(_ payload: RealtimePayload<WebsiteRealtimeRecord>) {
        Task {
            await websitesViewModel.applyRealtimeEvent(payload)
        }
    }

    public func handleIngestedFileEvent(_ payload: RealtimePayload<IngestedFileRealtimeRecord>) {
        Task {
            await ingestionViewModel.applyIngestedFileEvent(payload)
        }
    }

    public func handleFileJobEvent(_ payload: RealtimePayload<FileJobRealtimeRecord>) {
        Task {
            await ingestionViewModel.applyFileJobEvent(payload)
        }
    }
}
