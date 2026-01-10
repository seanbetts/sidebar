import Foundation
import Combine

@MainActor
public final class AppEnvironment: ObservableObject {
    public let container: ServiceContainer
    public var themeManager: ThemeManager
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

    @Published public private(set) var isAuthenticated: Bool = false
    @Published public var commandSelection: AppSection? = nil
    private var cancellables = Set<AnyCancellable>()

    public init(container: ServiceContainer, configError: EnvironmentConfigLoadError? = nil) {
        self.container = container
        self.themeManager = ThemeManager()
        self.chatViewModel = ChatViewModel(
            conversationsAPI: container.conversationsAPI,
            chatAPI: container.chatAPI,
            cache: container.cacheClient,
            themeManager: themeManager,
            streamClient: container.makeChatStreamClient(handler: nil)
        )
        let temporaryStore = TemporaryFileStore.shared
        self.notesViewModel = NotesViewModel(api: container.notesAPI, cache: container.cacheClient)
        self.filesViewModel = FilesViewModel(
            api: container.filesAPI,
            cache: container.cacheClient,
            temporaryStore: temporaryStore
        )
        self.ingestionViewModel = IngestionViewModel(
            api: container.ingestionAPI,
            cache: container.cacheClient,
            temporaryStore: temporaryStore
        )
        self.websitesViewModel = WebsitesViewModel(api: container.websitesAPI, cache: container.cacheClient)
        self.memoriesViewModel = MemoriesViewModel(api: container.memoriesAPI, cache: container.cacheClient)
        self.settingsViewModel = SettingsViewModel(
            settingsAPI: container.settingsAPI,
            skillsAPI: container.skillsAPI,
            cache: container.cacheClient
        )
        self.weatherViewModel = WeatherViewModel(api: container.weatherAPI)
        self.realtimeClient = container.makeRealtimeClient(handler: nil)
        self.configError = configError
        self.isAuthenticated = container.authSession.accessToken != nil

        if let authAdapter = container.authSession as? SupabaseAuthAdapter {
            authAdapter.$accessToken
                .sink { [weak self] _token in
                    self?.refreshAuthState()
                }
                .store(in: &cancellables)
        }

        if let realtimeClient = realtimeClient as? SupabaseRealtimeAdapter {
            realtimeClient.handler = self
        }
        realtimeClientStopStart()
    }

    public func refreshAuthState() {
        let wasAuthenticated = isAuthenticated
        isAuthenticated = container.authSession.accessToken != nil
        if wasAuthenticated && !isAuthenticated {
            container.cacheClient.clear()
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
        _ = payload
        Task {
            await ingestionViewModel.applyRealtimeEvent()
        }
    }

    public func handleFileJobEvent(_ payload: RealtimePayload<FileJobRealtimeRecord>) {
        _ = payload
        Task {
            await ingestionViewModel.applyRealtimeEvent()
        }
    }
}
