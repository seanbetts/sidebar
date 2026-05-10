import Foundation
import XCTest
import sideBarShared
@testable import sideBar

enum ChatViewModelTestsSupport {
    enum MockError: Error {
        case forced
    }

    struct TestNetworkStatus: NetworkStatusProviding {
        let isNetworkAvailable: Bool
        let isOffline: Bool
        let isServerReachable: Bool

        init(isNetworkAvailable: Bool, isOffline: Bool = false, isServerReachable: Bool = true) {
            self.isNetworkAvailable = isNetworkAvailable
            self.isOffline = isOffline
            self.isServerReachable = isServerReachable
        }
    }

    @MainActor
    final class ConversationsAPISpy: ConversationsAPIProviding, ConversationsProviding {
        private(set) var getCallCount = 0

        func list() async throws -> [Conversation] {
            return []
        }

        func get(id: String) async throws -> ConversationWithMessages {
            _ = id
            getCallCount += 1
            throw MockError.forced
        }

        func search(query: String, limit: Int) async throws -> [Conversation] {
            _ = query
            _ = limit
            return []
        }

        func delete(conversationId: String) async throws -> Conversation {
            _ = conversationId
            throw MockError.forced
        }

        func create(title: String) async throws -> Conversation {
            _ = title
            throw MockError.forced
        }

        func addMessage(conversationId: String, message: ConversationMessageCreate) async throws -> Conversation {
            _ = conversationId
            _ = message
            throw MockError.forced
        }

        func updateMessage(
            conversationId: String,
            messageId: String,
            message: ConversationMessageCreate
        ) async throws -> Conversation {
            _ = conversationId
            _ = messageId
            _ = message
            throw MockError.forced
        }

        func update(conversationId: String, updates: ConversationUpdateRequest) async throws -> Conversation {
            _ = conversationId
            _ = updates
            throw MockError.forced
        }
    }

    final class MockChatStreamClient: ChatStreamClient {
        weak var handler: ChatStreamEventHandler?
        private(set) var requests: [ChatStreamRequest] = []

        func connect(request: ChatStreamRequest) async throws {
            requests.append(request)
        }

        func disconnect() {
        }
    }

    struct MockConversationsAPI: ConversationsAPIProviding, ConversationsProviding {
        let listResult: Result<[Conversation], Error>
        let getResult: Result<ConversationWithMessages, Error>
        let searchResult: Result<[Conversation], Error>
        let deleteResult: Result<Conversation, Error>
        let createResult: Result<Conversation, Error>
        let addMessageResult: Result<Conversation, Error>
        let updateMessageResult: Result<Conversation, Error>
        let updateResult: Result<Conversation, Error>

        init(
            listResult: Result<[Conversation], Error>,
            getResult: Result<ConversationWithMessages, Error> = .failure(MockError.forced),
            searchResult: Result<[Conversation], Error> = .success([]),
            deleteResult: Result<Conversation, Error> = .success(Conversation(
                id: "deleted",
                title: "Deleted",
                titleGenerated: false,
                createdAt: "",
                updatedAt: "",
                messageCount: 0,
                firstMessage: nil,
                isArchived: true
            )),
            createResult: Result<Conversation, Error> = .failure(MockError.forced),
            addMessageResult: Result<Conversation, Error> = .failure(MockError.forced),
            updateMessageResult: Result<Conversation, Error> = .success(Conversation(
                id: "updated",
                title: "Updated",
                titleGenerated: false,
                createdAt: "",
                updatedAt: "",
                messageCount: 0,
                firstMessage: nil,
                isArchived: false
            )),
            updateResult: Result<Conversation, Error> = .failure(MockError.forced)
        ) {
            self.listResult = listResult
            self.getResult = getResult
            self.searchResult = searchResult
            self.deleteResult = deleteResult
            self.createResult = createResult
            self.addMessageResult = addMessageResult
            self.updateMessageResult = updateMessageResult
            self.updateResult = updateResult
        }

        func list() async throws -> [Conversation] {
            try listResult.get()
        }

        func get(id: String) async throws -> ConversationWithMessages {
            _ = id
            return try getResult.get()
        }

        func search(query: String, limit: Int) async throws -> [Conversation] {
            _ = query
            _ = limit
            return try searchResult.get()
        }

        func delete(conversationId: String) async throws -> Conversation {
            _ = conversationId
            return try deleteResult.get()
        }

        func create(title: String) async throws -> Conversation {
            _ = title
            return try createResult.get()
        }

        func addMessage(conversationId: String, message: ConversationMessageCreate) async throws -> Conversation {
            _ = conversationId
            _ = message
            return try addMessageResult.get()
        }

        func updateMessage(
            conversationId: String,
            messageId: String,
            message: ConversationMessageCreate
        ) async throws -> Conversation {
            _ = conversationId
            _ = messageId
            _ = message
            return try updateMessageResult.get()
        }

        func update(conversationId: String, updates: ConversationUpdateRequest) async throws -> Conversation {
            _ = conversationId
            _ = updates
            return try updateResult.get()
        }
    }
}

@MainActor
class ChatViewModelTestCase: XCTestCase {
    private static let sharedAPIClient = APIClient(
        config: APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { "token-123" }
        )
    )
    private static let sharedThemeManager: ThemeManager = {
        let defaults = UserDefaults(suiteName: "ChatViewModelTestsTheme") ?? .standard
        defaults.removePersistentDomain(forName: "ChatViewModelTestsTheme")
        return ThemeManager(userDefaults: defaults)
    }()
    private static var retainedPersistenceControllers: [PersistenceController] = []
    private static var retainedViewModels: [ChatViewModel] = []

    override func tearDown() {
        ChatViewModelTestsURLProtocolMock.requestHandler = nil
        super.tearDown()
    }

    func makeViewModel<API: ConversationsProviding & ConversationsAPIProviding>(
        api: API,
        cache: CacheClient,
        chatAPI: (any ChatAPIProviding)? = nil,
        networkStatus: ChatViewModelTestsSupport.TestNetworkStatus? = nil,
        persistence: PersistenceController? = nil,
        offlineStore: OfflineStore? = nil,
        draftStorage: DraftStorage? = nil,
        onboardingAPI: (any OnboardingProviding)? = nil,
        scratchpadStore: ScratchpadStore? = nil,
        ingestionAPI: IngestionAPI? = nil,
        streamClient: (any ChatStreamClient)? = nil,
        onOnboardingStateRefreshRequested: (() -> Void)? = nil,
        onOpenNoteRequested: ((String) -> Void)? = nil,
        onCloseNoteRequested: ((String) -> Bool)? = nil,
        requestContextProvider: (() -> ChatRequestContext?)? = nil,
        workspaceActionDispatcher: ((WorkspaceAction) -> Void)? = nil,
        attachmentPollingInitialDelayNanoseconds: UInt64 = 1_500_000_000,
        attachmentPollingIntervalNanoseconds: UInt64 = 5_000_000_000,
        soulCalibrationRetryBackoffNanoseconds: UInt64 = 1_000_000_000
    ) -> ChatViewModel {
        let chatAPI = chatAPI ?? ChatAPI(client: Self.sharedAPIClient)
        let themeManager = Self.sharedThemeManager
        let defaults = UserDefaults(suiteName: "ChatViewModelTests") ?? .standard
        defaults.removePersistentDomain(forName: "ChatViewModelTests")
        let toastCenter = ToastCenter()
        let persistence = persistence ?? PersistenceController(inMemory: true)
        Self.retainedPersistenceControllers.append(persistence)
        let resolvedDraftStorage = draftStorage ?? DraftStorage(container: persistence.container)
        let resolvedIngestionAPI = ingestionAPI ?? IngestionAPI(client: Self.sharedAPIClient)
        let effectiveNetworkStatus = networkStatus ?? ChatViewModelTestsSupport.TestNetworkStatus(isNetworkAvailable: true)
        let resolvedStreamClient = streamClient ?? ChatViewModelTestsSupport.MockChatStreamClient()
        let chatStore = ChatStore(
            conversationsAPI: api,
            cache: cache,
            offlineStore: offlineStore,
            networkStatus: effectiveNetworkStatus
        )
        let viewModel = ChatViewModel(
            network: ChatNetworkCoordinator(
                chatAPI: chatAPI,
                conversationsAPI: api,
                onboardingAPI: onboardingAPI,
                ingestionAPI: resolvedIngestionAPI,
                streamClient: resolvedStreamClient,
                networkStatus: effectiveNetworkStatus
            ),
            storage: ChatStorageCoordinator(
                cache: cache,
                chatStore: chatStore,
                draftStorage: resolvedDraftStorage,
                notesStore: nil,
                websitesStore: nil,
                ingestionStore: nil,
                scratchpadStore: scratchpadStore
            ),
            ui: ChatUICoordinator(
                themeManager: themeManager,
                toastCenter: toastCenter,
                userDefaults: defaults,
                clock: { Date(timeIntervalSince1970: 0) },
                onOnboardingStateRefreshRequested: onOnboardingStateRefreshRequested,
                onOpenNoteRequested: onOpenNoteRequested,
                onCloseNoteRequested: onCloseNoteRequested,
                requestContextProvider: requestContextProvider,
                attachmentPollingInitialDelayNanoseconds: attachmentPollingInitialDelayNanoseconds,
                attachmentPollingIntervalNanoseconds: attachmentPollingIntervalNanoseconds,
                soulCalibrationRetryBackoffNanoseconds: soulCalibrationRetryBackoffNanoseconds
            )
        )
        viewModel.workspaceActionDispatcher = workspaceActionDispatcher
        Self.retainedViewModels.append(viewModel)
        return viewModel
    }

    func makeIngestionAPIForAttachmentPollingTest(
        statusCode: Int = 500,
        responseBody: String = "{\"detail\":\"internal\"}"
    ) -> IngestionAPI {
        let config = APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { "token-123" }
        )
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [ChatViewModelTestsURLProtocolMock.self]
        let session = URLSession(configuration: sessionConfig)
        ChatViewModelTestsURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("files/file-1/meta") == true)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(responseBody.utf8))
        }
        return IngestionAPI(client: APIClient(config: config, session: session), session: session)
    }

    func makeIngestionAPIForAttachmentCancelTest(
        requestHandler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> IngestionAPI {
        let config = APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { "token-123" }
        )
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [ChatViewModelTestsURLProtocolMock.self]
        let session = URLSession(configuration: sessionConfig)
        ChatViewModelTestsURLProtocolMock.requestHandler = requestHandler
        return IngestionAPI(client: APIClient(config: config, session: session), session: session)
    }
}
