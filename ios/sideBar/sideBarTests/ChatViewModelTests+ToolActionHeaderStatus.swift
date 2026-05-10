import XCTest
import sideBarShared
@testable import sideBar

extension ChatViewModelTests {
    func testFailedConfirmationUsesHeaderStatusAndRetriesOriginalDecision() async {
        let chatAPI = ToolActionAPISpy(
            resolveResults: [
                .failure(ChatViewModelTestsSupport.MockError.forced),
                .success(makeConfirmationAcceptedResponse(confirmationId: "confirm-1"))
            ]
        )
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: TestCacheClient(),
            chatAPI: chatAPI
        )
        viewModel.messages = [
            Message(
                id: "assistant-1",
                role: .assistant,
                content: "Please confirm that you want to delete this note.",
                status: .complete,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "",
                error: nil
            )
        ]
        viewModel.toolActionsByMessageId["assistant-1"] = [
            ChatToolAction(
                id: "confirm-1",
                kind: .confirmation,
                summary: "Delete note note-1?",
                toolName: "Delete Note",
                guardReason: "destructive_action",
                undoSupported: true,
                expiresAt: nil,
                entityType: nil,
                entityId: nil,
                status: .pending
            )
        ]

        viewModel.handleToolAction(viewModel.toolActions(for: "assistant-1")[0], decision: .accept)

        XCTAssertEqual(viewModel.activeTool?.name, "Delete Note")
        XCTAssertEqual(viewModel.activeTool?.status, .running)
        await chatAPI.waitForResolveCallCount(1)
        await assertEventually(
            viewModel.toolActions(for: "assistant-1").first?.status == .failed,
            message: "Expected failed confirmation to remain retryable"
        )
        XCTAssertEqual(viewModel.activeTool?.status, .error)

        viewModel.handleToolAction(viewModel.toolActions(for: "assistant-1")[0])
        await chatAPI.waitForResolveCallCount(2)
        await assertEventually(
            viewModel.toolActions(for: "assistant-1").first?.status == .accepted,
            message: "Expected accepted confirmation to resolve after retry"
        )
        await assertEventually(
            viewModel.activeTool?.status == .success,
            message: "Expected successful confirmation retry to update the header status"
        )

        XCTAssertEqual(chatAPI.resolveCalls.map(\.decision), [.accept, .accept])
        XCTAssertEqual(viewModel.activeTool?.name, "Delete Note")
    }

    func testFailedUndoUsesHeaderStatusAndCanRetry() async {
        let chatAPI = ToolActionAPISpy(
            undoResults: [
                .failure(ChatViewModelTestsSupport.MockError.forced),
                .success(ChatToolUndoResponse(success: true, data: nil))
            ]
        )
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: TestCacheClient(),
            chatAPI: chatAPI
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

        viewModel.handleToolAction(viewModel.toolActions(for: "assistant-1")[0])

        XCTAssertEqual(viewModel.activeTool?.name, "Undo note deletion")
        XCTAssertEqual(viewModel.activeTool?.status, .running)
        await chatAPI.waitForUndoCallCount(1)
        await assertEventually(
            viewModel.toolActions(for: "assistant-1").first?.status == .failed,
            message: "Expected failed undo to remain retryable"
        )
        XCTAssertEqual(viewModel.activeTool?.status, .error)

        viewModel.handleToolAction(viewModel.toolActions(for: "assistant-1")[0])
        await chatAPI.waitForUndoCallCount(2)
        await assertEventually(
            viewModel.toolActions(for: "assistant-1").first?.status == .undone,
            message: "Expected successful undo retry to resolve the inline action"
        )
        await assertEventually(
            viewModel.activeTool?.status == .success,
            message: "Expected successful undo retry to update the header status"
        )

        XCTAssertEqual(chatAPI.undoCalls, ["undo-1", "undo-1"])
    }
}

@MainActor
private final class ToolActionAPISpy: ChatAPIProviding {
    struct ResolveCall {
        let confirmationId: String
        let decision: ChatToolActionDecision
    }

    private var resolveResults: [Result<ChatToolActionResponse, Error>]
    private var undoResults: [Result<ChatToolUndoResponse, Error>]
    private(set) var resolveCalls: [ResolveCall] = []
    private(set) var undoCalls: [String] = []

    init(
        resolveResults: [Result<ChatToolActionResponse, Error>] = [],
        undoResults: [Result<ChatToolUndoResponse, Error>] = []
    ) {
        self.resolveResults = resolveResults
        self.undoResults = undoResults
    }

    func generateTitle(conversationId: String) async throws -> ChatTitleResponse {
        _ = conversationId
        throw ChatViewModelTestsSupport.MockError.forced
    }

    func resolveToolConfirmation(
        confirmationId: String,
        decision: ChatToolActionDecision
    ) async throws -> ChatToolActionResponse {
        resolveCalls.append(ResolveCall(confirmationId: confirmationId, decision: decision))
        guard !resolveResults.isEmpty else {
            throw ChatViewModelTestsSupport.MockError.forced
        }
        return try resolveResults.removeFirst().get()
    }

    func undoToolAction(undoToken: String) async throws -> ChatToolUndoResponse {
        undoCalls.append(undoToken)
        guard !undoResults.isEmpty else {
            throw ChatViewModelTestsSupport.MockError.forced
        }
        return try undoResults.removeFirst().get()
    }

    func waitForResolveCallCount(_ count: Int) async {
        await waitUntil { self.resolveCalls.count >= count }
    }

    func waitForUndoCallCount(_ count: Int) async {
        await waitUntil { self.undoCalls.count >= count }
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<20 {
            if condition() {
                return
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
    }
}

private func makeConfirmationAcceptedResponse(confirmationId: String) -> ChatToolActionResponse {
    ChatToolActionResponse(
        success: true,
        events: [
            ChatToolActionResponseEvent(
                type: "tool_confirmation_resolved",
                data: AnyCodable([
                    "confirmation_id": confirmationId,
                    "decision": "accept",
                    "resolved_at": "2026-05-10T12:00:00Z"
                ])
            )
        ]
    )
}

@MainActor
private func assertEventually(
    _ condition: @autoclosure @escaping @MainActor () -> Bool,
    message: String,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    for _ in 0..<20 {
        if condition() {
            return
        }

        await Task.yield()
        try? await Task.sleep(nanoseconds: 25_000_000)
    }

    XCTFail(message, file: file, line: line)
}
