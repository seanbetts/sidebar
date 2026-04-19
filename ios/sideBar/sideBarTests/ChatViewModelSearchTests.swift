import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class ChatViewModelSearchTests: XCTestCase {
    private static let sharedAPIClient = APIClient(
        config: APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { nil }
        )
    )
    private static let sharedThemeManager: ThemeManager = {
        let defaults = UserDefaults(suiteName: "ChatViewModelSearchTestsTheme") ?? .standard
        defaults.removePersistentDomain(forName: "ChatViewModelSearchTestsTheme")
        return ThemeManager(userDefaults: defaults)
    }()
    private static var retainedViewModels: [ChatViewModel] = []

    func testSearchConversationsFiltersArchivedResults() async throws {
        let searchResults = [
            Conversation(
                id: "conv-1",
                title: "Planning",
                titleGenerated: false,
                createdAt: "2026-01-01T00:00:00Z",
                updatedAt: "2026-01-02T00:00:00Z",
                messageCount: 1,
                firstMessage: "Roadmap draft",
                isArchived: false
            ),
            Conversation(
                id: "conv-2",
                title: "Archived planning",
                titleGenerated: false,
                createdAt: "2026-01-01T00:00:00Z",
                updatedAt: "2026-01-02T00:00:00Z",
                messageCount: 1,
                firstMessage: "Old roadmap",
                isArchived: true
            )
        ]
        let api = ChatViewModelTestsSupport.MockConversationsAPI(
            listResult: .success([]),
            searchResult: .success(searchResults)
        )
        let viewModel = makeViewModel(api: api, cache: TestCacheClient())

        let matches = try await viewModel.searchConversations(query: "  planning  ", limit: 20)

        XCTAssertEqual(matches.map(\.id), ["conv-1"])
    }

    private func makeViewModel<API: ConversationsProviding & ConversationsAPIProviding>(
        api: API,
        cache: CacheClient
    ) -> ChatViewModel {
        let defaults = UserDefaults(suiteName: "ChatViewModelSearchTests") ?? .standard
        defaults.removePersistentDomain(forName: "ChatViewModelSearchTests")
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
