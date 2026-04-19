import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class ChatStartupStabilityTests: XCTestCase {
    private static let sharedAPIClient = APIClient(
        config: APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { nil }
        )
    )
    private static let sharedThemeManager: ThemeManager = {
        let defaults = UserDefaults(suiteName: "ChatStartupStabilityTestsTheme") ?? .standard
        defaults.removePersistentDomain(forName: "ChatStartupStabilityTestsTheme")
        return ThemeManager(userDefaults: defaults)
    }()
    private static var retainedViewModels: [ChatViewModel] = []

    func testSortedConversationsByUpdatedAtHandlesFractionalAndNonFractionalTimestamps() {
        let cache = TestCacheClient()
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache
        )
        let conversations = [
            Conversation(
                id: "oldest",
                title: "Oldest",
                titleGenerated: false,
                createdAt: "2026-01-01T00:00:00Z",
                updatedAt: "2026-01-01T00:00:00Z",
                messageCount: 0,
                firstMessage: nil,
                isArchived: false
            ),
            Conversation(
                id: "newest",
                title: "Newest",
                titleGenerated: false,
                createdAt: "2026-01-01T00:00:00Z",
                updatedAt: "2026-01-01T00:00:00.123Z",
                messageCount: 0,
                firstMessage: nil,
                isArchived: false
            )
        ]

        let sorted = viewModel.sortedConversationsByUpdatedAt(conversations)

        XCTAssertEqual(sorted.map { $0.id }, ["newest", "oldest"])
    }

    private func makeViewModel<API: ConversationsProviding & ConversationsAPIProviding>(
        api: API,
        cache: CacheClient
    ) -> ChatViewModel {
        let defaults = UserDefaults(suiteName: "ChatStartupStabilityTests") ?? .standard
        defaults.removePersistentDomain(forName: "ChatStartupStabilityTests")
        let toastCenter = ToastCenter()
        let chatStore = ChatStore(conversationsAPI: api, cache: cache)
        let viewModel = ChatViewModel(
            network: ChatNetworkCoordinator(
                chatAPI: ChatAPI(client: Self.sharedAPIClient),
                conversationsAPI: api,
                ingestionAPI: IngestionAPI(client: Self.sharedAPIClient),
                streamClient: ChatViewModelTestsSupport.MockChatStreamClient(),
                networkStatus: ChatViewModelTestsSupport.TestNetworkStatus(isNetworkAvailable: true)
            ),
            storage: ChatStorageCoordinator(
                cache: cache,
                chatStore: chatStore,
                notesStore: nil,
                websitesStore: nil,
                ingestionStore: nil,
                scratchpadStore: nil
            ),
            ui: ChatUICoordinator(
                themeManager: Self.sharedThemeManager,
                toastCenter: toastCenter,
                userDefaults: defaults,
                clock: { Date(timeIntervalSince1970: 0) }
            )
        )
        Self.retainedViewModels.append(viewModel)
        return viewModel
    }
}
