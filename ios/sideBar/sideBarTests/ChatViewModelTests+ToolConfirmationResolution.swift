import XCTest
import sideBarShared
@testable import sideBar

extension ChatViewModelTests {
    func testResolvedConfirmationDoesNotReconstructInlineActionAfterBackendRefresh() throws {
        try assertResolvedConfirmationDoesNotReconstructInlineActionAfterBackendRefresh(decision: .decline)
        try assertResolvedConfirmationDoesNotReconstructInlineActionAfterBackendRefresh(decision: .accept)
    }

    func testExpiredPersistedConfirmationDoesNotReconstructInlineAction() {
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: TestCacheClient()
        )
        viewModel.messages = [confirmationMessage(
            id: "assistant-1",
            confirmationId: "confirm-1",
            expiresAt: "1969-12-31T23:59:59Z"
        )]

        let actions = viewModel.toolActions(for: "assistant-1")

        XCTAssertTrue(actions.isEmpty)
    }

    func testAcceptedConfirmationResolutionDoesNotPersistMessageFromFrontend() async throws {
        let api = ToolConfirmationUpdateMessageAPISpy()
        let viewModel = makeViewModel(
            api: api,
            cache: TestCacheClient()
        )
        viewModel.selectedConversationId = "conversation-1"
        viewModel.messages = [confirmationMessage(id: "assistant-1", confirmationId: "confirm-1")]

        viewModel.handle(event: ChatStreamEvent(
            type: .toolConfirmationResolved,
            data: AnyCodable([
                "confirmation_id": "confirm-1",
                "decision": "accept",
                "resolved_at": "2026-05-09T00:06:00Z"
            ])
        ))
        await api.waitForUpdateMessageCall()

        XCTAssertTrue(
            api.updateMessageCalls.isEmpty,
            "Confirmation resolution must not write assistant transcript state from the frontend."
        )
    }

    func testDeclinedConfirmationResolutionDoesNotPersistMessageFromFrontend() async throws {
        let api = ToolConfirmationUpdateMessageAPISpy()
        let viewModel = makeViewModel(
            api: api,
            cache: TestCacheClient()
        )
        viewModel.selectedConversationId = "conversation-1"
        viewModel.messages = [confirmationMessage(id: "assistant-1", confirmationId: "confirm-1")]

        viewModel.handle(event: ChatStreamEvent(
            type: .toolConfirmationResolved,
            data: AnyCodable([
                "confirmation_id": "confirm-1",
                "decision": "decline",
                "resolved_at": "2026-05-09T00:06:00Z"
            ])
        ))
        await api.waitForUpdateMessageCall()

        XCTAssertTrue(
            api.updateMessageCalls.isEmpty,
            "Decline acknowledgement must be persisted by the backend conversation action."
        )
    }
}

private extension ChatViewModelTests {
    func confirmationMessage(
        id: String,
        confirmationId: String,
        expiresAt: String = "2026-05-09T00:05:00Z"
    ) -> Message {
        Message(
            id: id,
            role: .assistant,
            content: "Please confirm that you want to delete this note.",
            status: .complete,
            toolCalls: [
                ToolCall(
                    id: "tool-1",
                    name: "Delete Note",
                    parameters: ["note_id": AnyCodable("note-1")],
                    status: .pending,
                    skillId: "notes",
                    iconKey: "notes",
                    confirmationId: confirmationId,
                    confirmationSummary: "Delete note note-1?",
                    confirmationGuardReason: "destructive_action",
                    confirmationUndoSupported: true,
                    confirmationExpiresAt: expiresAt
                )
            ],
            needsNewline: nil,
            timestamp: "2026-05-09T00:04:00Z",
            error: nil
        )
    }

    func assertResolvedConfirmationDoesNotReconstructInlineActionAfterBackendRefresh(
        decision: ChatToolActionDecision,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: TestCacheClient()
        )
        let messageId = "assistant-\(decision.rawValue)"
        viewModel.messages = [confirmationMessage(
            id: messageId,
            confirmationId: "confirm-\(decision.rawValue)"
        )]

        viewModel.handle(event: ChatStreamEvent(
            type: .toolConfirmationResolved,
            data: AnyCodable([
                "confirmation_id": "confirm-\(decision.rawValue)",
                "decision": decision.rawValue,
                "resolved_at": "2026-05-09T00:06:00Z"
            ])
        ))

        let refreshedMessage = try XCTUnwrap(viewModel.messages.first, file: file, line: line)
        viewModel.toolActionsByMessageId.removeAll()
        viewModel.messages = [refreshedMessage]

        XCTAssertTrue(viewModel.toolActions(for: messageId).isEmpty, file: file, line: line)
    }
}

@MainActor
private final class ToolConfirmationUpdateMessageAPISpy: ConversationsAPIProviding, ConversationsProviding {
    struct UpdateMessageCall {
        let conversationId: String
        let messageId: String
        let message: ConversationMessageCreate
    }

    private(set) var updateMessageCalls: [UpdateMessageCall] = []

    func list() async throws -> [Conversation] {
        []
    }

    func get(id: String) async throws -> ConversationWithMessages {
        ConversationWithMessages(
            id: id,
            title: "Chat",
            titleGenerated: false,
            createdAt: "2026-05-10T12:00:00Z",
            updatedAt: "2026-05-10T12:00:00Z",
            messageCount: 0,
            firstMessage: nil,
            isArchived: false,
            messages: []
        )
    }

    func search(query: String, limit: Int) async throws -> [Conversation] {
        _ = query
        _ = limit
        return []
    }

    func delete(conversationId: String) async throws -> Conversation {
        defaultConversation(id: conversationId)
    }

    func create(title: String) async throws -> Conversation {
        defaultConversation(id: "created", title: title)
    }

    func addMessage(conversationId: String, message: ConversationMessageCreate) async throws -> Conversation {
        _ = message
        return defaultConversation(id: conversationId)
    }

    func updateMessage(
        conversationId: String,
        messageId: String,
        message: ConversationMessageCreate
    ) async throws -> Conversation {
        updateMessageCalls.append(UpdateMessageCall(
            conversationId: conversationId,
            messageId: messageId,
            message: message
        ))
        return defaultConversation(id: conversationId)
    }

    func update(conversationId: String, updates: ConversationUpdateRequest) async throws -> Conversation {
        _ = updates
        return defaultConversation(id: conversationId)
    }

    func waitForUpdateMessageCall() async {
        await waitForUpdateMessageCallCount(1)
    }

    func waitForUpdateMessageCallCount(_ count: Int) async {
        for _ in 0..<20 {
            if updateMessageCalls.count >= count {
                return
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
    }

    private func defaultConversation(id: String, title: String = "Chat") -> Conversation {
        Conversation(
            id: id,
            title: title,
            titleGenerated: false,
            createdAt: "2026-05-10T12:00:00Z",
            updatedAt: "2026-05-10T12:00:00Z",
            messageCount: 0,
            firstMessage: nil,
            isArchived: false
        )
    }
}
