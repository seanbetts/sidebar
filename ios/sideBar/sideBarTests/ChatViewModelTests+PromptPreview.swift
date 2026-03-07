import XCTest
import sideBarShared
@testable import sideBar

@MainActor
extension ChatViewModelTests {
    func testPromptPreviewEventStoresPromptDiagnostics() async {
        let cache = TestCacheClient()
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache
        )

        let event = ChatStreamEvent(
            type: .promptPreview,
            data: AnyCodable([
                "system_prompt": "System prompt text",
                "first_message_prompt": "First message prompt text",
                "system_prompt_sections": [
                    [
                        "id": "message_context",
                        "title": "Message Context",
                        "source": "system_template",
                        "chars": 2335
                    ]
                ],
                "first_message_prompt_sections": [
                    [
                        "id": "first_message",
                        "title": "First Message Context",
                        "source": "first_message_template",
                        "chars": 1137
                    ]
                ],
                "prompt_report": [
                    "system_prompt": [
                        "total_chars": 3690,
                        "max_chars": 40000,
                        "truncated": false,
                        "sections": [
                            [
                                "id": "message_context",
                                "title": "Message Context",
                                "source": "system_template",
                                "chars": 2335
                            ]
                        ]
                    ],
                    "first_message_prompt": [
                        "total_chars": 1137,
                        "max_chars": 8000,
                        "truncated": false,
                        "sections": [
                            [
                                "id": "first_message",
                                "title": "First Message Context",
                                "source": "first_message_template",
                                "chars": 1137
                            ]
                        ]
                    ]
                ],
                "request_budget_report": requestBudgetReportPayload()
            ])
        )

        viewModel.handle(event: event)

        XCTAssertEqual(viewModel.promptPreview?.systemPrompt, "System prompt text")
        XCTAssertEqual(viewModel.promptPreview?.firstMessagePrompt, "First message prompt text")
        XCTAssertEqual(viewModel.promptPreview?.systemPromptSections.count, 1)
        XCTAssertEqual(viewModel.promptPreview?.systemPromptSections.first?.id, "message_context")
        XCTAssertEqual(viewModel.promptPreview?.firstMessagePromptSections.count, 1)
        XCTAssertEqual(viewModel.promptPreview?.firstMessagePromptSections.first?.chars, 1137)
        XCTAssertEqual(viewModel.promptPreview?.promptReport?.systemPrompt?.totalChars, 3690)
        XCTAssertEqual(viewModel.promptPreview?.promptReport?.firstMessagePrompt?.maxChars, 8000)
        XCTAssertEqual(viewModel.promptPreview?.requestBudgetReport?.provider, "anthropic")
        XCTAssertEqual(viewModel.promptPreview?.requestBudgetReport?.toolSchemaChars, 1250)
    }

    func testPromptPreviewEventDispatchesAgentWorkspaceSurface() async {
        let cache = TestCacheClient()
        var dispatchedActions: [WorkspaceAction] = []
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache,
            workspaceActionDispatcher: { action in
                dispatchedActions.append(action)
            }
        )

        let event = ChatStreamEvent(
            type: .promptPreview,
            data: AnyCodable([
                "system_prompt": "System prompt text",
                "first_message_prompt": "First message prompt text",
                "system_prompt_sections": [
                    [
                        "id": "message_context",
                        "title": "Message Context",
                        "source": "system_template",
                        "chars": 2335
                    ]
                ],
                "first_message_prompt_sections": [
                    [
                        "id": "first_message",
                        "title": "First Message Context",
                        "source": "first_message_template",
                        "chars": 1137
                    ]
                ],
                "prompt_report": [
                    "system_prompt": [
                        "total_chars": 3690,
                        "max_chars": 40000,
                        "truncated": false,
                        "sections": []
                    ]
                ],
                "request_budget_report": requestBudgetReportPayload()
            ])
        )

        viewModel.handle(event: event)

        guard case .presentAgentSurface(let surface, let pane) = dispatchedActions.first else {
            return XCTFail("Expected prompt preview to dispatch an agent workspace surface")
        }

        XCTAssertEqual(pane, .primary)
        XCTAssertEqual(surface.surfaceType, .markdown)
        XCTAssertEqual(surface.surfaceId, "prompt-preview")
        XCTAssertEqual(surface.title, "System Prompt")
        XCTAssertFalse(surface.capabilities.canRefresh)
        XCTAssertTrue(surface.capabilities.canClose)
        XCTAssertFalse(surface.capabilities.canPin)
        XCTAssertFalse(surface.capabilities.canInspectData)
        XCTAssertEqual(
            surface.payload["summary"],
            "Generated from current system and first-message prompts."
        )

        let markdown = surface.payload["markdown"] ?? ""
        XCTAssertTrue(markdown.contains("System Prompt"))
        XCTAssertTrue(markdown.contains("System prompt text"))
        XCTAssertTrue(markdown.contains("First Message Prompt"))
        XCTAssertTrue(markdown.contains("First message prompt text"))
        XCTAssertTrue(markdown.contains("Prompt Report"))
        XCTAssertTrue(markdown.contains("Request Budget"))
    }

    private func requestBudgetReportPayload() -> [String: Any] {
        [
            "provider": "anthropic",
            "model": "claude-sonnet-4-6",
            "context_window_chars": 200000,
            "reserved_output_chars": 20000,
            "available_input_chars": 177000,
            "provider_framing_chars": 3000,
            "system_prompt_chars": 3690,
            "bootstrap_history_chars": 1100,
            "conversation_history_chars": 250,
            "current_message_chars": 10,
            "tool_schema_chars": 1250,
            "total_input_chars": 6300,
            "overflow_chars": 0,
            "within_budget": true,
            "failure_reason": NSNull(),
            "trimming_applied": false,
            "compaction_applied": false
        ]
    }
}

final class ChatViewModelTestsURLProtocolMock: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            XCTFail("Request handler not set")
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
    }
}
