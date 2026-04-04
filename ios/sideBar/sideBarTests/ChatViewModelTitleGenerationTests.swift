import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class ChatViewModelTitleGenerationTests: XCTestCase {
    private static let sharedAPIClient = APIClient(
        config: APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { nil }
        )
    )

    override func tearDown() {
        ChatViewModelTestsURLProtocolMock.requestHandler = nil
        super.tearDown()
    }

    func testFinalizeStreamingRequestsTitleBeforeRefreshingActiveConversation() async {
        let cache = TestCacheClient()
        let conversationsAPI = ChatViewModelTestsSupport.MockConversationsAPI(
            listResult: .success([]),
            getResult: .success(
                ConversationWithMessages(
                    id: "conv-1",
                    title: "New Chat",
                    titleGenerated: false,
                    createdAt: "2026-01-02T00:00:00Z",
                    updatedAt: "2026-01-02T00:00:00Z",
                    messageCount: 0,
                    firstMessage: nil,
                    isArchived: nil,
                    messages: []
                )
            )
        )
        var titleRequestCount = 0
        let chatAPI = makeChatAPIForTitleGenerationTest {
            titleRequestCount += 1
        }
        let viewModel = makeViewModel(
            api: conversationsAPI,
            cache: cache,
            chatAPI: chatAPI
        )
        let conversation = Conversation(
            id: "conv-1",
            title: "New Chat",
            titleGenerated: false,
            createdAt: "2026-01-02T00:00:00Z",
            updatedAt: "2026-01-02T00:00:00Z",
            messageCount: 0,
            firstMessage: nil,
            isArchived: nil
        )
        viewModel.chatStore.upsertConversation(conversation)
        viewModel.selectedConversationId = conversation.id
        viewModel.streamingConversationId = conversation.id
        viewModel.messages = [
            Message(
                id: "user-1",
                role: .user,
                content: "Explain request budgeting",
                status: .complete,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2026-01-02T00:00:00Z",
                error: nil
            ),
            Message(
                id: "assistant-1",
                role: .assistant,
                content: "It tracks prompt, history, tools, and output reserves.",
                status: .streaming,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2026-01-02T00:00:01Z",
                error: nil
            )
        ]
        viewModel.beginStreamingMessage(assistantMessageId: "assistant-1")

        viewModel.finalizeStreaming(status: .complete)

        let requestedTitle = await waitForCondition {
            titleRequestCount == 1
        }

        XCTAssertTrue(requestedTitle)
        XCTAssertEqual(titleRequestCount, 1)
    }

    func testFinalizeStreamingRequestsTitleWhenConversationStartsWithAssistantKickoff() async {
        let cache = TestCacheClient()
        let conversationsAPI = ChatViewModelTestsSupport.MockConversationsAPI(
            listResult: .success([]),
            getResult: .success(
                ConversationWithMessages(
                    id: "conv-1",
                    title: "New Chat",
                    titleGenerated: false,
                    createdAt: "2026-01-02T00:00:00Z",
                    updatedAt: "2026-01-02T00:00:00Z",
                    messageCount: 0,
                    firstMessage: nil,
                    isArchived: nil,
                    messages: []
                )
            )
        )
        var titleRequestCount = 0
        let chatAPI = makeChatAPIForTitleGenerationTest {
            titleRequestCount += 1
        }
        let viewModel = makeViewModel(
            api: conversationsAPI,
            cache: cache,
            chatAPI: chatAPI
        )
        let conversation = Conversation(
            id: "conv-1",
            title: "New Chat",
            titleGenerated: false,
            createdAt: "2026-01-02T00:00:00Z",
            updatedAt: "2026-01-02T00:00:00Z",
            messageCount: 0,
            firstMessage: nil,
            isArchived: nil
        )
        viewModel.chatStore.upsertConversation(conversation)
        viewModel.selectedConversationId = conversation.id
        viewModel.streamingConversationId = conversation.id
        viewModel.messages = [
            Message(
                id: "assistant-kickoff",
                role: .assistant,
                content: "Hi, I'm Voss.",
                status: .complete,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2026-01-02T00:00:00Z",
                error: nil
            ),
            Message(
                id: "user-1",
                role: .user,
                content: "Help me plan the rest of today.",
                status: .complete,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2026-01-02T00:00:01Z",
                error: nil
            ),
            Message(
                id: "assistant-1",
                role: .assistant,
                content: "Let's make a simple plan.",
                status: .streaming,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2026-01-02T00:00:02Z",
                error: nil
            )
        ]
        viewModel.beginStreamingMessage(assistantMessageId: "assistant-1")

        viewModel.finalizeStreaming(status: .complete)

        let requestedTitle = await waitForCondition {
            titleRequestCount == 1
        }

        XCTAssertTrue(requestedTitle)
        XCTAssertEqual(titleRequestCount, 1)
    }

    private func makeViewModel<API: ConversationsProviding & ConversationsAPIProviding>(
        api: API,
        cache: CacheClient,
        chatAPI: ChatAPI
    ) -> ChatViewModel {
        let themeDefaults = UserDefaults(suiteName: "ChatViewModelTitleGenerationTheme")
            ?? .standard
        themeDefaults.removePersistentDomain(forName: "ChatViewModelTitleGenerationTheme")
        let themeManager = ThemeManager(userDefaults: themeDefaults)
        let uiDefaults = UserDefaults(suiteName: "ChatViewModelTitleGeneration")
            ?? .standard
        uiDefaults.removePersistentDomain(forName: "ChatViewModelTitleGeneration")
        let chatStore = ChatStore(conversationsAPI: api, cache: cache)
        let streamClient = ChatViewModelTestsSupport.MockChatStreamClient()
        let ingestionAPI = IngestionAPI(client: Self.sharedAPIClient)

        return ChatViewModel(
            network: ChatNetworkCoordinator(
                chatAPI: chatAPI,
                conversationsAPI: api,
                ingestionAPI: ingestionAPI,
                streamClient: streamClient,
                networkStatus: ChatViewModelTestsSupport.TestNetworkStatus(
                    isNetworkAvailable: true
                )
            ),
            storage: ChatStorageCoordinator(
                cache: cache,
                chatStore: chatStore
            ),
            ui: ChatUICoordinator(
                themeManager: themeManager,
                userDefaults: uiDefaults,
                clock: { Date(timeIntervalSince1970: 0) }
            )
        )
    }

    private func makeChatAPIForTitleGenerationTest(
        onRequest: @escaping () -> Void = {}
    ) -> ChatAPI {
        let config = APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { nil }
        )
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [ChatViewModelTestsURLProtocolMock.self]
        let session = URLSession(configuration: sessionConfig)
        ChatViewModelTestsURLProtocolMock.requestHandler = { request in
            onRequest()
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(
                request.url?.absoluteString.hasSuffix("/chat/generate-title") == true
            )
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = "{\"title\":\"Budgeting Overview\",\"fallback\":false}"
            return (response, Data(payload.utf8))
        }
        return ChatAPI(client: APIClient(config: config, session: session))
    }

    private func waitForCondition(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        pollNanoseconds: UInt64 = 0,
        condition: @escaping () -> Bool
    ) async -> Bool {
        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            if condition() {
                return true
            }
            if pollNanoseconds == 0 {
                await Task.yield()
            } else {
                try? await Task.sleep(nanoseconds: pollNanoseconds)
            }
        }
        return condition()
    }
}
