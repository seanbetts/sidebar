import XCTest
import sideBarShared
@testable import sideBar

extension ChatViewModelTests {
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
            "Help me get started with Notes in sideBar. Give me a short guided intro and one simple first win."
        )
        XCTAssertEqual(viewModel.selectedConversationId, created.id)
        XCTAssertEqual(viewModel.messages.first?.role, .user)
        XCTAssertEqual(viewModel.messages.first?.content, sentRequest.message)
        XCTAssertEqual(viewModel.messages.last?.role, .assistant)
        XCTAssertTrue(viewModel.messages.last?.content.isEmpty == true)
    }
}
