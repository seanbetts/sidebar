import Foundation

public final class ServiceContainer {
    public let config: EnvironmentConfig
    public let authSession: AuthSession
    public let apiClient: APIClient
    public let cacheClient: CacheClient

    public let chatAPI: ChatAPI
    public let conversationsAPI: ConversationsAPI
    public let notesAPI: NotesAPI
    public let filesAPI: FilesAPI
    public let ingestionAPI: IngestionAPI
    public let websitesAPI: WebsitesAPI
    public let memoriesAPI: MemoriesAPI
    public let settingsAPI: SettingsAPI
    public let skillsAPI: SkillsAPI
    public let weatherAPI: WeatherAPI
    public let placesAPI: PlacesAPI
    public let scratchpadAPI: ScratchpadAPI
    public let tasksAPI: TasksAPI
    public let deviceTokensAPI: DeviceTokensAPI

    public init(config: EnvironmentConfig, authSession: AuthSession, cacheClient: CacheClient) {
        self.config = config
        self.authSession = authSession
        self.cacheClient = cacheClient
        self.apiClient = APIClient(config: APIClientConfig(
            baseUrl: config.apiBaseUrl,
            accessTokenProvider: { authSession.accessToken }
        ))

        self.chatAPI = ChatAPI(client: apiClient)
        self.conversationsAPI = ConversationsAPI(client: apiClient)
        self.notesAPI = NotesAPI(client: apiClient)
        self.filesAPI = FilesAPI(client: apiClient)
        self.ingestionAPI = IngestionAPI(client: apiClient)
        self.websitesAPI = WebsitesAPI(client: apiClient)
        self.memoriesAPI = MemoriesAPI(client: apiClient)
        self.settingsAPI = SettingsAPI(client: apiClient)
        self.skillsAPI = SkillsAPI(client: apiClient)
        self.weatherAPI = WeatherAPI(client: apiClient)
        self.placesAPI = PlacesAPI(client: apiClient)
        self.scratchpadAPI = ScratchpadAPI(client: apiClient)
        self.tasksAPI = TasksAPI(client: apiClient)
        self.deviceTokensAPI = DeviceTokensAPI(client: apiClient)
    }

    public func makeChatStreamClient(handler: ChatStreamEventHandler?) -> ChatStreamClient {
        URLSessionChatStreamClient(
            baseUrl: config.apiBaseUrl,
            accessTokenProvider: { [authSession] in authSession.accessToken },
            handler: handler
        )
    }

    public func makeRealtimeClient(handler: RealtimeEventHandler?) -> RealtimeClient {
        SupabaseRealtimeAdapter(config: config, handler: handler)
    }
}
