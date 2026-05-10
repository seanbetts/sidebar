import XCTest
import sideBarShared
@testable import sideBar

extension ChatViewModelTests {
    func testToolConfirmationRequestedAddsInlineActionToStreamingMessage() {
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: TestCacheClient()
        )
        viewModel.messages = [
            Message(
                id: "assistant-1",
                role: .assistant,
                content: "",
                status: .streaming,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "",
                error: nil
            )
        ]
        viewModel.currentStreamMessageId = "assistant-1"

        viewModel.handle(event: ChatStreamEvent(
            type: .toolConfirmationRequested,
            data: AnyCodable([
                "confirmation_id": "confirm-1",
                "tool_call_id": "tool-1",
                "tool_name": "Delete Note",
                "summary": "Delete note note-1?",
                "guard_reason": "This deletes content.",
                "undo_supported": true,
                "expires_at": "2026-05-09T00:05:00Z"
            ])
        ))

        let actions = viewModel.toolActions(for: "assistant-1")
        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions.first?.kind, .confirmation)
        XCTAssertEqual(actions.first?.id, "confirm-1")
        XCTAssertEqual(actions.first?.summary, "Delete note note-1?")
        XCTAssertEqual(actions.first?.status, .pending)
        XCTAssertEqual(actions.first?.undoSupported, true)
        XCTAssertEqual(
            viewModel.messages.first?.content,
            "Please confirm that you want to delete this note."
        )
    }

    func testToolConfirmationRequestedParsesLiveDestructiveToolPayload() {
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: TestCacheClient()
        )
        viewModel.messages = [
            Message(
                id: "assistant-1",
                role: .assistant,
                content: "",
                status: .streaming,
                toolCalls: [
                    ToolCall(
                        id: "toolu_01JWPzVV7KZyqAAmTg5qyx1W",
                        name: "Delete Note",
                        parameters: ["note_id": AnyCodable("note-1")],
                        status: .pending,
                        skillId: "notes",
                        iconKey: "note"
                    )
                ],
                needsNewline: nil,
                timestamp: "",
                error: nil
            )
        ]
        viewModel.currentStreamMessageId = "assistant-1"

        viewModel.handle(event: ChatStreamEvent(
            type: .toolConfirmationRequested,
            data: AnyCodable([
                "confirmation_id": "confirm-1",
                "expires_at": "2026-05-09T00:05:00Z",
                "guard_reason": "destructive_action",
                "icon_key": "note",
                "parameters": ["note_id": "note-1"],
                "skill_id": "notes",
                "summary": "Delete note note-1?",
                "tool_call_id": "toolu_01JWPzVV7KZyqAAmTg5qyx1W",
                "tool_name": "Delete Note",
                "undo_supported": true
            ])
        ))

        let actions = viewModel.toolActions(for: "assistant-1")
        let toolCall = viewModel.messages.first?.toolCalls?.first
        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions.first?.id, "confirm-1")
        XCTAssertEqual(actions.first?.summary, "Delete note note-1?")
        XCTAssertEqual(actions.first?.toolName, "Delete Note")
        XCTAssertEqual(actions.first?.guardReason, "destructive_action")
        XCTAssertEqual(toolCall?.confirmationId, "confirm-1")
        XCTAssertEqual(toolCall?.confirmationSummary, "Delete note note-1?")
        XCTAssertEqual(
            viewModel.messages.first?.content,
            "Please confirm that you want to delete this note."
        )
    }

    func testToolConfirmationDeclineAppendsAssistantAcknowledgement() {
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: TestCacheClient()
        )
        viewModel.messages = [
            Message(
                id: "assistant-1",
                role: .assistant,
                content: "",
                status: .complete,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "",
                error: nil
            )
        ]
        viewModel.currentStreamMessageId = "assistant-1"

        viewModel.handle(event: ChatStreamEvent(
            type: .toolConfirmationRequested,
            data: AnyCodable([
                "confirmation_id": "confirm-1",
                "tool_call_id": "tool-1",
                "tool_name": "Delete Note",
                "summary": "Delete note note-1?",
                "guard_reason": "destructive_action",
                "undo_supported": true,
                "expires_at": "2026-05-09T00:05:00Z"
            ])
        ))
        viewModel.handle(event: ChatStreamEvent(
            type: .toolConfirmationResolved,
            data: AnyCodable([
                "confirmation_id": "confirm-1",
                "decision": "decline",
                "resolved_at": "2026-05-09T00:06:00Z"
            ])
        ))

        XCTAssertEqual(
            viewModel.messages.first?.content,
            """
            Please confirm that you want to delete this note.

            Okay, I won't delete this note.
            """
        )
        XCTAssertEqual(viewModel.toolActions(for: "assistant-1").first?.status, .declined)
    }

    func testUndoAvailableAddsInlineActionToResolvedToolActionMessage() {
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: TestCacheClient()
        )
        viewModel.activeToolActionMessageId = "assistant-1"

        viewModel.handle(event: ChatStreamEvent(
            type: .undoAvailable,
            data: AnyCodable([
                "undo_token": "undo-1",
                "summary": "Restore deleted note",
                "entity_type": "note",
                "entity_id": "note-1",
                "expires_at": "2026-05-09T00:05:00Z"
            ])
        ))

        let actions = viewModel.toolActions(for: "assistant-1")
        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions.first?.kind, .undo)
        XCTAssertEqual(actions.first?.id, "undo-1")
        XCTAssertEqual(actions.first?.summary, "Restore deleted note")
        XCTAssertEqual(actions.first?.entityType, "note")
        XCTAssertEqual(actions.first?.status, .pending)
    }

    func testSuccessfulNoteUndoAppendsAssistantAcknowledgement() {
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: TestCacheClient()
        )
        viewModel.messages = [
            Message(
                id: "assistant-1",
                role: .assistant,
                content: "Deleted this note.",
                status: .complete,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "",
                error: nil
            )
        ]
        viewModel.toolActionsByMessageId["assistant-1"] = [
            ChatToolAction(
                id: "undo-1",
                kind: .undo,
                summary: "Undo note deletion?",
                toolName: nil,
                guardReason: nil,
                undoSupported: false,
                expiresAt: nil,
                entityType: "note",
                entityId: "note-1",
                status: .pending
            )
        ]

        viewModel.handleSuccessfulUndo(
            viewModel.toolActions(for: "assistant-1")[0],
            messageId: "assistant-1"
        )

        XCTAssertEqual(
            viewModel.messages.first?.content,
            """
            Deleted this note.

            Restored this note.
            """
        )
        XCTAssertEqual(viewModel.toolActions(for: "assistant-1").first?.status, .undone)
    }

    func testSuccessfulNoteUndoPersistsAssistantAcknowledgementToBackend() async {
        let api = UpdateMessageAPISpy()
        let viewModel = makeViewModel(
            api: api,
            cache: TestCacheClient()
        )
        viewModel.selectedConversationId = "conversation-1"
        viewModel.messages = [
            Message(
                id: "assistant-1",
                role: .assistant,
                content: "Deleted this note.",
                status: .complete,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2026-05-10T12:00:00Z",
                error: nil
            )
        ]
        viewModel.toolActionsByMessageId["assistant-1"] = [
            ChatToolAction(
                id: "undo-1",
                kind: .undo,
                summary: "Undo note deletion?",
                toolName: nil,
                guardReason: nil,
                undoSupported: false,
                expiresAt: nil,
                entityType: "note",
                entityId: "note-1",
                status: .pending
            )
        ]

        viewModel.handleSuccessfulUndo(
            viewModel.toolActions(for: "assistant-1")[0],
            messageId: "assistant-1"
        )
        await api.waitForUpdateMessageCall()

        XCTAssertEqual(api.updateMessageCalls.count, 1)
        XCTAssertEqual(api.updateMessageCalls.first?.conversationId, "conversation-1")
        XCTAssertEqual(api.updateMessageCalls.first?.messageId, "assistant-1")
        XCTAssertEqual(
            api.updateMessageCalls.first?.message.content,
            """
            Deleted this note.

            Restored this note.
            """
        )
    }

    func testToolActionsReconstructPendingConfirmationFromPersistedToolCall() {
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: TestCacheClient()
        )
        viewModel.messages = [
            Message(
                id: "assistant-1",
                role: .assistant,
                content: "",
                status: .complete,
                toolCalls: [
                    ToolCall(
                        id: "tool-1",
                        name: "Delete Note",
                        parameters: ["note_id": AnyCodable("note-1")],
                        status: .pending,
                        confirmationId: "confirm-1",
                        confirmationSummary: "Delete note note-1?",
                        confirmationGuardReason: "destructive_action",
                        confirmationUndoSupported: true,
                        confirmationExpiresAt: "2026-05-09T00:05:00Z"
                    )
                ],
                needsNewline: nil,
                timestamp: "",
                error: nil
            )
        ]

        let actions = viewModel.toolActions(for: "assistant-1")

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions.first?.id, "confirm-1")
        XCTAssertEqual(actions.first?.kind, .confirmation)
        XCTAssertEqual(actions.first?.summary, "Delete note note-1?")
        XCTAssertEqual(actions.first?.guardReason, "destructive_action")
        XCTAssertEqual(actions.first?.undoSupported, true)
        XCTAssertEqual(actions.first?.status, .pending)
    }
}

@MainActor
private final class UpdateMessageAPISpy: ConversationsAPIProviding, ConversationsProviding {
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
        for _ in 0..<20 {
            if !updateMessageCalls.isEmpty {
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
