import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class ChatViewModelAssistantSettingsTests: XCTestCase {
    private static let apiClient = APIClient(
        config: APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { nil }
        )
    )

    func testAssistantIdentityUpdateEventPublishesSettingsUpdate() async {
        var receivedUpdate: AssistantSettingsRealtimeUpdate?
        let viewModel = makeViewModel { update in
            receivedUpdate = update
        }
        let event = ChatStreamEvent(
            type: .collectionInvalidated,
            data: AnyCodable([
                "targets": ["assistant_settings"]
            ])
        )

        viewModel.handle(event: event)

        XCTAssertTrue(receivedUpdate?.requiresRefresh ?? false)
    }

    func testAssistantSettingsEventWithoutPayloadRequestsRefresh() async {
        var receivedUpdate: AssistantSettingsRealtimeUpdate?
        let viewModel = makeViewModel { update in
            receivedUpdate = update
        }

        viewModel.handle(event: ChatStreamEvent(
            type: .collectionInvalidated,
            data: AnyCodable([
                "targets": ["assistant_settings"]
            ])
        ))

        XCTAssertTrue(receivedUpdate?.requiresRefresh ?? false)
    }

    func testProfileUserSettingsUpdateEventRequestsRefresh() async {
        var receivedUpdate: AssistantSettingsRealtimeUpdate?
        let viewModel = makeViewModel { update in
            receivedUpdate = update
        }
        let event = ChatStreamEvent(
            type: .collectionInvalidated,
            data: AnyCodable([
                "targets": ["profile", "preferences"]
            ])
        )

        viewModel.handle(event: event)

        XCTAssertTrue(receivedUpdate?.requiresRefresh ?? false)
    }

    private func makeViewModel(
        onAssistantSettingsUpdated: @escaping (AssistantSettingsRealtimeUpdate) -> Void
    ) -> ChatViewModel {
        let cache = TestCacheClient()
        let defaults = UserDefaults(suiteName: "ChatViewModelAssistantSettingsTests") ?? .standard
        defaults.removePersistentDomain(forName: "ChatViewModelAssistantSettingsTests")
        let toastCenter = ToastCenter()
        let conversationsAPI = AssistantSettingsConversationsAPI()
        let chatStore = ChatStore(conversationsAPI: conversationsAPI, cache: cache)
        return ChatViewModel(
            network: ChatNetworkCoordinator(
                chatAPI: ChatAPI(client: Self.apiClient),
                conversationsAPI: conversationsAPI,
                ingestionAPI: IngestionAPI(client: Self.apiClient),
                streamClient: AssistantSettingsStreamClient(),
                networkStatus: AssistantSettingsNetworkStatus()
            ),
            storage: ChatStorageCoordinator(
                cache: cache,
                chatStore: chatStore
            ),
            ui: ChatUICoordinator(
                themeManager: ThemeManager(userDefaults: defaults),
                toastCenter: toastCenter,
                userDefaults: defaults,
                clock: { Date(timeIntervalSince1970: 0) },
                onAssistantSettingsUpdated: onAssistantSettingsUpdated
            )
        )
    }
}

private struct AssistantSettingsNetworkStatus: NetworkStatusProviding {
    let isNetworkAvailable = true
    let isOffline = false
}

private final class AssistantSettingsStreamClient: ChatStreamClient {
    weak var handler: ChatStreamEventHandler?

    func connect(request: ChatStreamRequest) async throws {
        _ = request
    }

    func disconnect() {
    }
}

private struct AssistantSettingsConversationsAPI: ConversationsAPIProviding, ConversationsProviding {
    func list() async throws -> [Conversation] { [] }
    func get(id: String) async throws -> ConversationWithMessages { throw AssistantSettingsTestError.forced }
    func search(query: String, limit: Int) async throws -> [Conversation] { [] }
    func delete(conversationId: String) async throws -> Conversation { throw AssistantSettingsTestError.forced }
    func create(title: String) async throws -> Conversation { throw AssistantSettingsTestError.forced }
    func addMessage(conversationId: String, message: ConversationMessageCreate) async throws -> Conversation {
        throw AssistantSettingsTestError.forced
    }
    func updateMessage(
        conversationId: String,
        messageId: String,
        message: ConversationMessageCreate
    ) async throws -> Conversation {
        throw AssistantSettingsTestError.forced
    }
    func update(conversationId: String, updates: ConversationUpdateRequest) async throws -> Conversation {
        throw AssistantSettingsTestError.forced
    }
}

private enum AssistantSettingsTestError: Error {
    case forced
}
