import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class ChatRefreshAdapterTests: ChatViewModelTestCase {
    func testActivationRefreshClearsPreviousConversationLoadError() async {
        let conversation = Conversation(
            id: "conversation-1",
            title: "Recovered chat",
            titleGenerated: false,
            createdAt: "2026-04-26T15:00:00Z",
            updatedAt: "2026-04-26T15:00:00Z",
            messageCount: 0,
            firstMessage: nil,
            isArchived: false
        )
        let api = SequencedConversationsAPI(results: [
            .failure(APIClientError.missingToken),
            .success([conversation])
        ])
        let viewModel = makeViewModel(api: api, cache: TestCacheClient())

        await viewModel.loadConversations(force: true)

        XCTAssertNotNil(viewModel.errorMessage)

        let adapter = ChatRefreshAdapter(viewModel: viewModel)
        await adapter.refresh(
            plan: RefreshPlan(
                trigger: .coldLaunch,
                targets: [.chatList],
                requiresQueueReplayFirst: false
            )
        )

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.conversations.map(\.id), ["conversation-1"])
    }
}

@MainActor
private final class SequencedConversationsAPI: ConversationsAPIProviding, ConversationsProviding {
    private var results: [Result<[Conversation], Error>]

    init(results: [Result<[Conversation], Error>]) {
        self.results = results
    }

    func list() async throws -> [Conversation] {
        guard !results.isEmpty else { return [] }
        return try results.removeFirst().get()
    }

    func get(id: String) async throws -> ConversationWithMessages {
        _ = id
        throw APIClientError.unknown
    }

    func search(query: String, limit: Int) async throws -> [Conversation] {
        _ = query
        _ = limit
        return []
    }

    func delete(conversationId: String) async throws -> Conversation {
        _ = conversationId
        throw APIClientError.unknown
    }

    func create(title: String) async throws -> Conversation {
        _ = title
        throw APIClientError.unknown
    }

    func addMessage(conversationId: String, message: ConversationMessageCreate) async throws -> Conversation {
        _ = conversationId
        _ = message
        throw APIClientError.unknown
    }

    func update(conversationId: String, updates: ConversationUpdateRequest) async throws -> Conversation {
        _ = conversationId
        _ = updates
        throw APIClientError.unknown
    }
}
