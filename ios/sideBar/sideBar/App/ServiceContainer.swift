import Foundation
import sideBarShared

/// Holds shared API clients and factories used to build app feature services.
public final class ServiceContainer {
    /// Environment configuration used for API and realtime setup.
    public let config: EnvironmentConfig
    /// Auth session providing access tokens and refresh behavior.
    public let authSession: AuthSession
    /// Base HTTP API client used by feature API wrappers.
    public let apiClient: APIClient
    /// Cache client used by stores for short-lived response caching.
    public let cacheClient: CacheClient

    /// Chat API wrapper for assistant message operations.
    public let chatAPI: ChatAPI
    /// Conversations API wrapper for chat thread operations.
    public let conversationsAPI: ConversationsAPI
    /// Notes API wrapper for note tree and note content operations.
    public let notesAPI: NotesAPI
    /// Files API wrapper for file browser operations.
    public let filesAPI: FilesAPI
    /// Ingestion API wrapper for upload and ingestion metadata operations.
    public let ingestionAPI: IngestionAPI
    /// Websites API wrapper for website list and sync operations.
    public let websitesAPI: any WebsitesProviding
    /// Memories API wrapper for memory retrieval operations.
    public let memoriesAPI: MemoriesAPI
    /// Settings API wrapper for user settings operations.
    public let settingsAPI: SettingsAPI
    /// Skills API wrapper for assistant skill discovery and execution.
    public let skillsAPI: SkillsAPI
    /// Weather API wrapper for forecast and current conditions.
    public let weatherAPI: WeatherAPI
    /// Places API wrapper for place search and lookup operations.
    public let placesAPI: PlacesAPI
    /// Scratchpad API wrapper for scratchpad content operations.
    public let scratchpadAPI: ScratchpadAPI
    /// Tasks API wrapper for task list and mutation operations.
    public let tasksAPI: TasksAPI
    /// Device tokens API wrapper for push token registration.
    public let deviceTokensAPI: DeviceTokensAPI

    /// Builds a service container and initializes feature API wrappers from shared dependencies.
    public init(
        config: EnvironmentConfig,
        authSession: AuthSession,
        cacheClient: CacheClient,
        websitesAPI: (any WebsitesProviding)? = nil
    ) {
        self.config = config
        self.authSession = authSession
        self.cacheClient = cacheClient
        self.apiClient = APIClient(config: APIClientConfig(
            baseUrl: config.apiBaseUrl,
            accessTokenProvider: { authSession.authorizationToken },
            refreshAuthIfNeeded: {
                await authSession.refreshSession()
                return authSession.authorizationToken != nil
            }
        ))

        self.chatAPI = ChatAPI(client: apiClient)
        self.conversationsAPI = ConversationsAPI(client: apiClient)
        self.notesAPI = NotesAPI(client: apiClient)
        self.filesAPI = FilesAPI(client: apiClient)
        self.ingestionAPI = IngestionAPI(client: apiClient)
        self.websitesAPI = websitesAPI ?? WebsitesAPI(client: apiClient)
        self.memoriesAPI = MemoriesAPI(client: apiClient)
        self.settingsAPI = SettingsAPI(client: apiClient)
        self.skillsAPI = SkillsAPI(client: apiClient)
        self.weatherAPI = WeatherAPI(client: apiClient)
        self.placesAPI = PlacesAPI(client: apiClient)
        self.scratchpadAPI = ScratchpadAPI(client: apiClient)
        self.tasksAPI = TasksAPI(client: apiClient)
        self.deviceTokensAPI = DeviceTokensAPI(client: apiClient)
    }

    /// Creates a chat streaming client bound to the current auth session token provider.
    public func makeChatStreamClient(handler: ChatStreamEventHandler?) -> ChatStreamClient {
        URLSessionChatStreamClient(
            baseUrl: config.apiBaseUrl,
            accessTokenProvider: { [authSession] in authSession.authorizationToken },
            handler: handler
        )
    }

    /// Creates a realtime client configured from the active environment settings.
    public func makeRealtimeClient(handler: RealtimeEventHandler?) -> RealtimeClient {
        SupabaseRealtimeAdapter(config: config, handler: handler)
    }
}
