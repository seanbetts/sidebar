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
    public let notesAPI: any NotesProviding
    /// Files API wrapper for file browser operations.
    public let filesAPI: FilesAPI
    /// Ingestion API wrapper for upload and ingestion metadata operations.
    public let ingestionAPI: any IngestionProviding
    /// Websites API wrapper for website list and sync operations.
    public let websitesAPI: any WebsitesProviding
    /// Memories API wrapper for memory retrieval operations.
    public let memoriesAPI: MemoriesAPI
    /// Settings API wrapper for user settings operations.
    public let settingsAPI: SettingsAPI
    /// Internal diagnostics API wrapper for notification diagnostics operations.
    public let internalDiagnosticsAPI: InternalDiagnosticsAPI
    /// Onboarding API wrapper for onboarding state operations.
    public let onboardingAPI: OnboardingAPI
    /// Skills API wrapper for assistant skill discovery and execution.
    public let skillsAPI: SkillsAPI
    /// Weather API wrapper for forecast and current conditions.
    public let weatherAPI: WeatherAPI
    /// Places API wrapper for place search and lookup operations.
    public let placesAPI: PlacesAPI
    /// Scratchpad API wrapper for scratchpad content operations.
    public let scratchpadAPI: ScratchpadAPI
    /// Tasks API wrapper for task list and mutation operations.
    public let tasksAPI: any TasksProviding
    /// Device tokens API wrapper for push token registration.
    public let deviceTokensAPI: DeviceTokensAPI
    /// Password reset API wrapper for reset initiation from signed-out surfaces.
    public let passwordResetAPI: any PasswordResetRequesting
    /// Password recovery manager for recovery-link handling and completion.
    public let passwordRecoveryManager: any PasswordRecoveryManaging
    /// Password change manager for in-session credential updates.
    public let passwordChangeManager: any PasswordChanging
    /// Availability checks and rollout flags for native Apple Intelligence routes.
    public let appleIntelligenceAvailabilityProvider: any AppleIntelligenceAvailabilityProviding
    /// SideBar-owned language model boundary used by native Apple Intelligence features.
    public let languageModelService: any LanguageModelServicing
    /// Reusable speech transcription boundary for microphone, audio, and video sources.
    public let speechTranscriptionService: any SpeechTranscriptionServicing
    /// Privacy-safe diagnostics recorder for native intelligence route metadata.
    public let intelligenceDiagnosticsRecorder: any IntelligenceDiagnosticsRecording

    public var observableAuthSession: (any AuthSessionObserving)? {
        authSession as? any AuthSessionObserving
    }

    public var offlineAccessRestorer: (any OfflineAccessRestoring)? {
        authSession as? any OfflineAccessRestoring
    }

    public var signInRateLimiter: (any SignInRateLimitStatusProviding)? {
        authSession as? any SignInRateLimitStatusProviding
    }

    /// Builds a service container and initializes feature API wrappers from shared dependencies.
    public init(
        config: EnvironmentConfig,
        authSession: AuthSession,
        cacheClient: CacheClient,
        notesAPI: (any NotesProviding)? = nil,
        ingestionAPI: (any IngestionProviding)? = nil,
        tasksAPI: (any TasksProviding)? = nil,
        websitesAPI: (any WebsitesProviding)? = nil,
        deviceTokensAPI: DeviceTokensAPI? = nil,
        internalDiagnosticsAPI: InternalDiagnosticsAPI? = nil,
        passwordRecoveryManager: (any PasswordRecoveryManaging)? = nil,
        passwordChangeManager: (any PasswordChanging)? = nil,
        appleIntelligenceAvailabilityProvider: (any AppleIntelligenceAvailabilityProviding)? = nil,
        languageModelService: (any LanguageModelServicing)? = nil,
        speechTranscriptionService: (any SpeechTranscriptionServicing)? = nil,
        intelligenceDiagnosticsRecorder: (any IntelligenceDiagnosticsRecording)? = nil
    ) {
        self.config = config
        self.authSession = authSession
        self.cacheClient = cacheClient
        self.apiClient = APIClient(config: APIClientConfig(
            baseUrl: config.apiBaseUrl,
            accessTokenProvider: { authSession.authorizationToken },
            refreshAuthIfNeeded: {
                let previousToken = authSession.authorizationToken
                await authSession.refreshSession()
                guard let currentToken = authSession.authorizationToken else {
                    return false
                }
                return previousToken == nil || currentToken != previousToken
            },
            handleAuthRejectedForToken: { rejectedToken in
                if let scopedInvalidating = authSession as? AuthSessionTokenScopedInvalidating {
                    scopedInvalidating.markSessionReauthenticationRequiredAfterAuthorizationFailure(
                        rejectedToken: rejectedToken
                    )
                    return
                }
                (authSession as? AuthSessionInvalidating)?
                    .markSessionReauthenticationRequiredAfterAuthorizationFailure()
            }
        ))

        self.chatAPI = ChatAPI(client: apiClient)
        self.conversationsAPI = ConversationsAPI(client: apiClient)
        self.notesAPI = notesAPI ?? NotesAPI(client: apiClient)
        self.filesAPI = FilesAPI(client: apiClient)
        self.ingestionAPI = ingestionAPI ?? IngestionAPI(client: apiClient)
        self.websitesAPI = websitesAPI ?? WebsitesAPI(client: apiClient)
        self.memoriesAPI = MemoriesAPI(client: apiClient)
        self.settingsAPI = SettingsAPI(client: apiClient)
        self.internalDiagnosticsAPI = internalDiagnosticsAPI ?? InternalDiagnosticsAPI(client: apiClient)
        self.onboardingAPI = OnboardingAPI(client: apiClient)
        self.skillsAPI = SkillsAPI(client: apiClient)
        self.weatherAPI = WeatherAPI(client: apiClient)
        self.placesAPI = PlacesAPI(client: apiClient)
        self.scratchpadAPI = ScratchpadAPI(client: apiClient)
        self.tasksAPI = tasksAPI ?? TasksAPI(client: apiClient)
        self.deviceTokensAPI = deviceTokensAPI ?? DeviceTokensAPI(client: apiClient)
        self.passwordResetAPI = PasswordResetAPI(client: apiClient)
        self.passwordRecoveryManager =
            passwordRecoveryManager
            ?? (authSession as? any PasswordRecoveryManaging)
            ?? UnavailablePasswordRecoveryManager()
        self.passwordChangeManager =
            passwordChangeManager
            ?? (authSession as? any PasswordChanging)
            ?? UnavailablePasswordChangeManager()
        self.appleIntelligenceAvailabilityProvider =
            appleIntelligenceAvailabilityProvider ?? DefaultAppleIntelligenceAvailabilityProvider()
        self.languageModelService = languageModelService ?? FakeLanguageModelService()
        self.speechTranscriptionService = speechTranscriptionService ?? FakeSpeechTranscriptionService()
        self.intelligenceDiagnosticsRecorder =
            intelligenceDiagnosticsRecorder ?? OSLogIntelligenceDiagnosticsRecorder()
    }

    /// Creates a chat streaming client bound to the current auth session token provider.
    public func makeChatStreamClient(handler: ChatStreamEventHandler?) -> ChatStreamClient {
        URLSessionChatStreamClient(
            baseUrl: config.apiBaseUrl,
            accessTokenProvider: { [authSession] in authSession.authorizationToken },
            refreshAuthIfNeeded: { [authSession] in
                let previousToken = authSession.authorizationToken
                await authSession.refreshSession()
                guard let currentToken = authSession.authorizationToken else {
                    return false
                }
                return previousToken == nil || currentToken != previousToken
            },
            handleAuthRejectedForToken: { [authSession] rejectedToken in
                if let scopedInvalidating = authSession as? AuthSessionTokenScopedInvalidating {
                    scopedInvalidating.markSessionReauthenticationRequiredAfterAuthorizationFailure(
                        rejectedToken: rejectedToken
                    )
                    return
                }
                (authSession as? AuthSessionInvalidating)?
                    .markSessionReauthenticationRequiredAfterAuthorizationFailure()
            },
            handler: handler
        )
    }

    /// Creates a realtime client configured from the active environment settings.
    public func makeRealtimeClient(handler: RealtimeEventHandler?) -> RealtimeClient {
        if EnvironmentConfig.isRunningTestsOrPreviews() {
            return PlaceholderRealtimeClient()
        }
        return SupabaseRealtimeAdapter(config: config, handler: handler)
    }
}

private final class UnavailablePasswordRecoveryManager: PasswordRecoveryManaging {
    func startRecoverySession(from url: URL) async throws {
        _ = url
        throw AuthAdapterError.serviceUnavailable
    }

    func completePasswordReset(newPassword: String) async throws {
        _ = newPassword
        throw AuthAdapterError.serviceUnavailable
    }
}

private final class UnavailablePasswordChangeManager: PasswordChanging {
    func changePassword(newPassword: String) async throws {
        _ = newPassword
        throw AuthAdapterError.serviceUnavailable
    }
}
