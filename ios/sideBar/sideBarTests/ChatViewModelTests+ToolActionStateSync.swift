import XCTest
import sideBarShared
@testable import sideBar

extension ChatViewModelTests {
    func testUndoAcknowledgementSurvivesStaleConversationRefresh() {
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: TestCacheClient()
        )
        viewModel.selectedConversationId = "conversation-1"
        let staleAssistantMessage = Message(
            id: "assistant-1",
            role: .assistant,
            content: "Deleted this note.",
            status: .complete,
            toolCalls: [
                ToolCall(
                    id: "tool-1",
                    name: "Delete Note",
                    parameters: ["note_id": AnyCodable("note-1")],
                    status: .success,
                    skillId: "notes",
                    iconKey: "notes"
                )
            ],
            needsNewline: nil,
            timestamp: "2026-05-10T12:00:00Z",
            error: nil
        )
        viewModel.messages = [staleAssistantMessage]
        viewModel.chatStore.upsertConversationDetail(
            conversation(messages: [staleAssistantMessage]),
            persist: true
        )
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
        viewModel.chatStore.upsertConversationDetail(
            conversation(messages: [staleAssistantMessage]),
            persist: true
        )

        XCTAssertEqual(
            viewModel.messages.first?.content,
            """
            Deleted this note.

            Restored this note.
            """
        )
        XCTAssertEqual(viewModel.messages.first?.toolCalls?.first?.status, .success)
    }

    func testToolResultUpdatesCompletedActionMessageToolCall() {
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: TestCacheClient()
        )
        viewModel.messages = [
            Message(
                id: "assistant-1",
                role: .assistant,
                content: "Deleting this note now.",
                status: .complete,
                toolCalls: [
                    ToolCall(
                        id: "tool-1",
                        name: "Delete Note",
                        parameters: ["note_id": AnyCodable("note-1")],
                        status: .pending,
                        skillId: "notes",
                        iconKey: "notes"
                    )
                ],
                needsNewline: nil,
                timestamp: "2026-05-10T12:00:00Z",
                error: nil
            )
        ]
        viewModel.activeToolActionMessageId = "assistant-1"

        viewModel.handle(event: ChatStreamEvent(
            type: .toolResult,
            data: AnyCodable([
                "id": "tool-1",
                "name": "Delete Note",
                "parameters": ["note_id": "note-1"],
                "result": [
                    "success": true,
                    "summary": "Deleted note"
                ],
                "status": "success",
                "skill_id": "notes",
                "icon_key": "notes"
            ])
        ))

        XCTAssertEqual(viewModel.messages.first?.toolCalls?.count, 1)
        XCTAssertEqual(viewModel.messages.first?.toolCalls?.first?.status, .success)
        XCTAssertEqual(viewModel.messages.first?.toolCalls?.first?.name, "Delete Note")
    }
}

private extension ChatViewModelTests {
    func conversation(messages: [Message]) -> ConversationWithMessages {
        ConversationWithMessages(
            id: "conversation-1",
            title: "Chat",
            titleGenerated: false,
            createdAt: "2026-05-10T12:00:00Z",
            updatedAt: "2026-05-10T12:00:00Z",
            messageCount: messages.count,
            firstMessage: nil,
            isArchived: false,
            messages: messages
        )
    }
}
