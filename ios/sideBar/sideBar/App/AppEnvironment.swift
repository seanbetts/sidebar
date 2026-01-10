import Foundation
import Combine

@MainActor
public final class AppEnvironment: ObservableObject {
    public let container: ServiceContainer
    public var themeManager: ThemeManager
    public let chatViewModel: ChatViewModel
    public let notesViewModel: NotesViewModel
    public let configError: EnvironmentConfigLoadError?

    @Published public private(set) var isAuthenticated: Bool = false
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
        self.notesViewModel = NotesViewModel(api: container.notesAPI, cache: container.cacheClient)
        self.configError = configError
        self.isAuthenticated = container.authSession.accessToken != nil

        if let authAdapter = container.authSession as? SupabaseAuthAdapter {
            authAdapter.$accessToken
                .sink { [weak self] _token in
                    self?.refreshAuthState()
                }
                .store(in: &cancellables)
        }
    }

    public func refreshAuthState() {
        let wasAuthenticated = isAuthenticated
        isAuthenticated = container.authSession.accessToken != nil
        if wasAuthenticated && !isAuthenticated {
            container.cacheClient.clear()
        }
    }
}
