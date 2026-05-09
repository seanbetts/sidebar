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
