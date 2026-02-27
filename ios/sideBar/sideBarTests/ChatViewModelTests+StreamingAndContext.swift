import XCTest
import sideBarShared
@testable import sideBar

extension ChatViewModelTests {
    func testSendMessageIncludesRequestContextPayloadWhenProvided() async throws {
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
        let requestContextProvider: () -> ChatRequestContext? = {
            ChatRequestContext(
                openContext: [
                    "note": AnyCodable([
                        "id": "note-1",
                        "title": "Plan",
                        "path": "notes/plan.md",
                        "content": "draft content"
                    ])
                ],
                currentLocation: "Paris, France",
                currentLocationLevels: nil,
                currentWeather: [
                    "temperature_c": AnyCodable(21.0),
                    "weather_code": AnyCodable(2),
                    "is_day": AnyCodable(1)
                ],
                currentTimezone: "Europe/Paris"
            )
        }
        let viewModel = makeViewModel(
            api: api,
            cache: cache,
            streamClient: streamClient,
            requestContextProvider: requestContextProvider
        )

        await viewModel.sendMessage(text: "Hello")

        let sentRequest = try XCTUnwrap(streamClient.requests.first)
        XCTAssertEqual(sentRequest.currentLocation, "Paris, France")
        XCTAssertEqual(sentRequest.currentTimezone, "Europe/Paris")

        let openContext = try XCTUnwrap(sentRequest.openContext)
        let notePayload = openContext["note"]?.value as? [String: Any]
        XCTAssertEqual(notePayload?["id"] as? String, "note-1")
        XCTAssertEqual(notePayload?["title"] as? String, "Plan")
        XCTAssertEqual(notePayload?["path"] as? String, "notes/plan.md")

        let weather = try XCTUnwrap(sentRequest.currentWeather)
        XCTAssertEqual(weather["weather_code"]?.value as? Int, 2)
        XCTAssertEqual(weather["is_day"]?.value as? Int, 1)
    }

    func testReconcileMessagesPrefersLocalStreamingContentWhenIDsMatch() async {
        let cache = TestCacheClient()
        let viewModel = makeViewModel(api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])), cache: cache)
        let localStreaming = Message(
            id: "assistant-1",
            role: .assistant,
            content: "longer local content",
            status: .streaming,
            toolCalls: nil,
            needsNewline: nil,
            timestamp: "2026-01-02T00:00:00Z",
            error: nil
        )
        viewModel.streamingConversationId = "conv-1"
        viewModel.currentStreamMessageId = localStreaming.id
        viewModel.messages = [localStreaming]

        let incoming = [
            Message(
                id: "assistant-1",
                role: .assistant,
                content: "short",
                status: .streaming,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2026-01-02T00:00:00Z",
                error: nil
            )
        ]

        let reconciled = viewModel.reconcileMessages(incoming, for: "conv-1")
        XCTAssertEqual(reconciled.first?.content, localStreaming.content)
    }

    func testReconcileMessagesDoesNotAppendLocalStreamWhenServerHasStreamingAssistant() async {
        let cache = TestCacheClient()
        let viewModel = makeViewModel(api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])), cache: cache)
        viewModel.streamingConversationId = "conv-1"
        viewModel.currentStreamMessageId = "assistant-local"
        viewModel.messages = [
            Message(
                id: "assistant-local",
                role: .assistant,
                content: "local stream",
                status: .streaming,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2026-01-02T00:00:00Z",
                error: nil
            )
        ]

        let incoming = [
            Message(
                id: "assistant-server",
                role: .assistant,
                content: "server stream",
                status: .streaming,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2026-01-02T00:00:00Z",
                error: nil
            )
        ]

        let reconciled = viewModel.reconcileMessages(incoming, for: "conv-1")
        XCTAssertEqual(reconciled.count, 1)
        XCTAssertEqual(reconciled.first?.id, "assistant-server")
    }

    func testStartAttachmentPollingMarksAttachmentFailedWhenStatusRequestFails() async {
        let cache = TestCacheClient()
        let conversationsAPI = ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([]))
        let ingestionAPI = makeIngestionAPIForAttachmentPollingTest()
        let viewModel = makeViewModel(
            api: conversationsAPI,
            cache: cache,
            ingestionAPI: ingestionAPI
        )
        viewModel.attachments = [
            ChatAttachmentItem(
                id: "attachment-1",
                name: "report.pdf",
                status: .queued,
                stage: "queued",
                fileId: "file-1"
            )
        ]

        viewModel.startAttachmentPolling(id: "attachment-1", fileId: "file-1")
        try? await Task.sleep(nanoseconds: 2_200_000_000)

        let attachment = viewModel.attachments.first(where: { $0.id == "attachment-1" })
        XCTAssertEqual(attachment?.status, .failed)
        XCTAssertEqual(attachment?.stage, "failed")
    }
}
