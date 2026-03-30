import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class ChatViewModelConversationLifecycleTests: ChatViewModelTestCase {
    func testPersistMessageSetsErrorOnFailure() async {
        let cache = TestCacheClient()
        let api = ChatViewModelTestsSupport.MockConversationsAPI(
            listResult: .success([]),
            addMessageResult: .failure(ChatViewModelTestsSupport.MockError.forced)
        )
        let viewModel = makeViewModel(api: api, cache: cache)
        let message = Message(
            id: "m1",
            role: .user,
            content: "Hello",
            status: .complete,
            toolCalls: nil,
            needsNewline: nil,
            timestamp: "2026-01-01T00:00:00Z",
            error: nil
        )

        await viewModel.persistMessage(conversationId: "c1", message: message)

        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testLoadConversationOfflineWithoutCacheSetsError() async {
        let cache = TestCacheClient()
        let api = ChatViewModelTestsSupport.ConversationsAPISpy()
        let viewModel = makeViewModel(
            api: api,
            cache: cache,
            networkStatus: ChatViewModelTestsSupport.TestNetworkStatus(isNetworkAvailable: false, isOffline: true)
        )

        await viewModel.loadConversation(id: "conv-1")

        XCTAssertEqual(viewModel.errorMessage, "This chat isn't available offline yet.")
        XCTAssertEqual(api.getCallCount, 0)
    }

    func testStartNewConversationCreatesAndSelectsConversation() async {
        let cache = TestCacheClient()
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
            createResult: .success(created)
        )
        let viewModel = makeViewModel(api: api, cache: cache)

        await viewModel.startNewConversation()

        XCTAssertEqual(viewModel.selectedConversationId, created.id)
        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertEqual(viewModel.conversations.first?.id, created.id)
    }

    func testOpenDraftConversationClearsSelectionAndActivatesDraft() async {
        let cache = TestCacheClient()
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache
        )
        viewModel.selectedConversationId = "conv-1"
        viewModel.messages = [
            Message(
                id: "msg-1",
                role: .assistant,
                content: "Hello",
                status: .complete,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2026-01-02T00:00:00Z",
                error: nil
            )
        ]
        viewModel.attachments = [
            ChatAttachmentItem(
                id: "attachment-1",
                name: "report.pdf",
                status: .ready,
                stage: "complete",
                fileId: "file-1"
            )
        ]
        viewModel.userDefaults.set("conv-1", forKey: AppStorageKeys.lastConversationId)

        await viewModel.openDraftConversation()

        XCTAssertNil(viewModel.selectedConversationId)
        XCTAssertTrue(viewModel.isDraftConversationActive)
        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertTrue(viewModel.attachments.isEmpty)
        XCTAssertNil(viewModel.userDefaults.string(forKey: AppStorageKeys.lastConversationId))
    }

    func testSelectConversationNilClearsDraftState() async {
        let cache = TestCacheClient()
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache
        )
        viewModel.isDraftConversationActive = true

        await viewModel.selectConversation(id: nil)

        XCTAssertFalse(viewModel.isDraftConversationActive)
    }
}
