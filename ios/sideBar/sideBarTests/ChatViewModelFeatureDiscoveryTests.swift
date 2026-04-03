import XCTest
import sideBarShared
@testable import sideBar

extension ChatViewModelTests {
    @MainActor
    private final class FeatureDiscoveryConversationsAPISpy: ConversationsAPIProviding, ConversationsProviding {
        private(set) var createdTitles: [String] = []
        let createdConversation: Conversation

        init(createdConversation: Conversation) {
            self.createdConversation = createdConversation
        }

        func list() async throws -> [Conversation] { [] }

        func get(id: String) async throws -> ConversationWithMessages {
            _ = id
            throw ChatViewModelTestsSupport.MockError.forced
        }

        func search(query: String, limit: Int) async throws -> [Conversation] {
            _ = query
            _ = limit
            return []
        }

        func delete(conversationId: String) async throws -> Conversation {
            _ = conversationId
            throw ChatViewModelTestsSupport.MockError.forced
        }

        func create(title: String) async throws -> Conversation {
            createdTitles.append(title)
            return createdConversation
        }

        func addMessage(conversationId: String, message: ConversationMessageCreate) async throws -> Conversation {
            _ = conversationId
            _ = message
            return createdConversation
        }

        func update(conversationId: String, updates: ConversationUpdateRequest) async throws -> Conversation {
            _ = conversationId
            _ = updates
            return createdConversation
        }
    }

    func testStartFeatureDiscoveryForNotesSendsOnboardingKickoffPrompt() async throws {
        let cache = TestCacheClient()
        let streamClient = ChatViewModelTestsSupport.MockChatStreamClient()
        let created = Conversation(
            id: "conv-new",
            title: "New Chat",
            titleGenerated: false,
            createdAt: "2026-01-02T00:00:00Z",
            updatedAt: "2026-01-02T00:00:00Z",
            messageCount: 0,
            firstMessage: nil,
            isArchived: nil
        )
        let api = ChatViewModelTestsSupport.MockConversationsAPI(
            listResult: .success([]),
            createResult: .success(created),
            addMessageResult: .success(created)
        )
        let viewModel = makeViewModel(
            api: api,
            cache: cache,
            streamClient: streamClient
        )

        await viewModel.startFeatureDiscovery(for: .notes)

        let sentRequest = try XCTUnwrap(streamClient.requests.first)
        XCTAssertEqual(
            sentRequest.message,
            OnboardingDiscoveryFeature.notes.kickoffPrompt
        )
        XCTAssertEqual(viewModel.selectedConversationId, created.id)
        XCTAssertEqual(viewModel.messages.first?.role, .user)
        XCTAssertEqual(viewModel.messages.first?.content, sentRequest.message)
        XCTAssertEqual(viewModel.messages.last?.role, .assistant)
        XCTAssertTrue(viewModel.messages.last?.content.isEmpty == true)
    }

    func testStartFeatureDiscoveryAlwaysCreatesNewConversationWhenExistingChatSelected() async throws {
        let cache = TestCacheClient()
        let streamClient = ChatViewModelTestsSupport.MockChatStreamClient()
        let created = Conversation(
            id: "conv-new",
            title: "New Chat",
            titleGenerated: false,
            createdAt: "2026-01-02T00:00:00Z",
            updatedAt: "2026-01-02T00:00:00Z",
            messageCount: 0,
            firstMessage: nil,
            isArchived: nil
        )
        let api = FeatureDiscoveryConversationsAPISpy(createdConversation: created)
        let viewModel = makeViewModel(
            api: api,
            cache: cache,
            streamClient: streamClient
        )
        viewModel.selectedConversationId = "conv-existing"
        viewModel.messages = [
            Message(
                id: "m-existing",
                role: .assistant,
                content: "Existing thread",
                status: .complete,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2026-01-02T00:00:00Z",
                error: nil
            )
        ]

        await viewModel.startFeatureDiscovery(for: .notes)

        XCTAssertEqual(api.createdTitles, ["New Chat"])
        XCTAssertEqual(viewModel.selectedConversationId, created.id)
        let sentRequest = try XCTUnwrap(streamClient.requests.first)
        XCTAssertEqual(sentRequest.conversationId, created.id)
        XCTAssertEqual(
            sentRequest.message,
            OnboardingDiscoveryFeature.notes.kickoffPrompt
        )
        XCTAssertEqual(viewModel.messages.first?.role, .user)
        XCTAssertEqual(viewModel.messages.first?.content, sentRequest.message)
        XCTAssertEqual(viewModel.messages.last?.role, .assistant)
        XCTAssertTrue(viewModel.messages.last?.content.isEmpty == true)
    }
}
