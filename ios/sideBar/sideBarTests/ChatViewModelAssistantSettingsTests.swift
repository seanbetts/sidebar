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
            type: .assistantIdentityUpdated,
            data: AnyCodable([
                "assistant_identity": ["name": "Navigator", "tone": "Calm"],
                "assistant_identity_meta": ["updated_at": "2026-02-18T00:00:00Z", "version": 2]
            ])
        )

        viewModel.handle(event: event)

        XCTAssertEqual(receivedUpdate?.assistantIdentity?.name, "Navigator")
        XCTAssertEqual(receivedUpdate?.assistantIdentityMeta?.version, 2)
        XCTAssertFalse(receivedUpdate?.requiresRefresh ?? true)
    }

    func testAssistantSettingsEventWithoutPayloadRequestsRefresh() async {
        var receivedUpdate: AssistantSettingsRealtimeUpdate?
        let viewModel = makeViewModel { update in
            receivedUpdate = update
        }

        viewModel.handle(event: ChatStreamEvent(type: .assistantSoulUpdated, data: nil))

        XCTAssertTrue(receivedUpdate?.requiresRefresh ?? false)
    }

    private func makeViewModel(
        onAssistantSettingsUpdated: @escaping (AssistantSettingsRealtimeUpdate) -> Void
    ) -> ChatViewModel {
        let cache = TestCacheClient()
        let defaults = UserDefaults(suiteName: "ChatViewModelAssistantSettingsTests") ?? .standard
        defaults.removePersistentDomain(forName: "ChatViewModelAssistantSettingsTests")
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
    func update(conversationId: String, updates: ConversationUpdateRequest) async throws -> Conversation {
        throw AssistantSettingsTestError.forced
    }
}

private enum AssistantSettingsTestError: Error {
    case forced
}
