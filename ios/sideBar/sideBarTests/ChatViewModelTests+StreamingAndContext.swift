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

    func testSendMessageIncludesAssistantMessageIdInStreamRequest() async throws {
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

        await viewModel.sendMessage(text: "Hello")

        let assistantMessage = try XCTUnwrap(
            viewModel.messages.last(where: { $0.role == .assistant })
        )
        let sentRequest = try XCTUnwrap(streamClient.requests.first)
        XCTAssertEqual(sentRequest.assistantMessageId, assistantMessage.id)
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

    func testReconcileMessagesPreservesLocalUserMessageWhenIncomingSnapshotIsStale() async {
        let cache = TestCacheClient()
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache
        )
        let userMessage = Message(
            id: "user-1",
            role: .user,
            content: "Where did my message go?",
            status: .complete,
            toolCalls: nil,
            needsNewline: nil,
            timestamp: "2026-01-02T00:00:00Z",
            error: nil
        )
        let localStreaming = Message(
            id: "assistant-1",
            role: .assistant,
            content: "Let me check",
            status: .streaming,
            toolCalls: nil,
            needsNewline: nil,
            timestamp: "2026-01-02T00:00:01Z",
            error: nil
        )
        viewModel.streamingConversationId = "conv-1"
        viewModel.currentStreamMessageId = localStreaming.id
        viewModel.messages = [userMessage, localStreaming]

        let reconciled = viewModel.reconcileMessages([], for: "conv-1")

        XCTAssertEqual(reconciled.map(\.id), ["user-1", "assistant-1"])
        XCTAssertEqual(reconciled.first?.content, userMessage.content)
        XCTAssertEqual(reconciled.last?.content, localStreaming.content)
    }

    func testReconcileMessagesPreservesMissingLocalUserWhenServerOnlyReturnsStreamingAssistant() async {
        let cache = TestCacheClient()
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache
        )
        let userMessage = Message(
            id: "user-1",
            role: .user,
            content: "Keep me visible",
            status: .complete,
            toolCalls: nil,
            needsNewline: nil,
            timestamp: "2026-01-02T00:00:00Z",
            error: nil
        )
        let localStreaming = Message(
            id: "assistant-1",
            role: .assistant,
            content: "longer local content",
            status: .streaming,
            toolCalls: nil,
            needsNewline: nil,
            timestamp: "2026-01-02T00:00:01Z",
            error: nil
        )
        viewModel.streamingConversationId = "conv-1"
        viewModel.currentStreamMessageId = localStreaming.id
        viewModel.messages = [userMessage, localStreaming]

        let incoming = [
            Message(
                id: "assistant-1",
                role: .assistant,
                content: "short",
                status: .streaming,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2026-01-02T00:00:01Z",
                error: nil
            )
        ]

        let reconciled = viewModel.reconcileMessages(incoming, for: "conv-1")

        XCTAssertEqual(reconciled.map(\.id), ["user-1", "assistant-1"])
        XCTAssertEqual(reconciled.last?.content, localStreaming.content)
    }

    func testIsSameMessageSnapshotTreatsSyntheticToolNewlineAsEquivalent() async {
        let cache = TestCacheClient()
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache
        )
        let toolCalls = [
            ToolCall(
                id: "tool-1",
                name: "Search",
                parameters: [:],
                status: .success
            )
        ]
        let local = Message(
            id: "assistant-1",
            role: .assistant,
            content: "Found this\n\nHere is the answer",
            status: .complete,
            toolCalls: toolCalls,
            needsNewline: false,
            timestamp: "2026-01-02T00:00:01Z",
            error: nil
        )
        let incoming = Message(
            id: "assistant-1",
            role: .assistant,
            content: "Found thisHere is the answer",
            status: .complete,
            toolCalls: toolCalls,
            needsNewline: nil,
            timestamp: "2026-01-02T00:00:01Z",
            error: nil
        )

        XCTAssertTrue(viewModel.isSameMessageSnapshot(current: [local], incoming: [incoming]))
    }

    func testIsSameMessageSnapshotMatchesSyntheticToolNewlineAfterExistingParagraphBreak() async {
        let cache = TestCacheClient()
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache
        )
        let toolCalls = [
            ToolCall(
                id: "tool-1",
                name: "Search",
                parameters: [:],
                status: .success
            )
        ]
        let local = Message(
            id: "assistant-1",
            role: .assistant,
            content: "Intro paragraph\n\nTool result\n\nFinal answer",
            status: .complete,
            toolCalls: toolCalls,
            needsNewline: false,
            timestamp: "2026-01-02T00:00:01Z",
            error: nil
        )
        let incoming = Message(
            id: "assistant-1",
            role: .assistant,
            content: "Intro paragraph\n\nTool resultFinal answer",
            status: .complete,
            toolCalls: toolCalls,
            needsNewline: nil,
            timestamp: "2026-01-02T00:00:01Z",
            error: nil
        )

        XCTAssertTrue(viewModel.isSameMessageSnapshot(current: [local], incoming: [incoming]))
    }

    func testStartAttachmentPollingMarksAttachmentFailedWhenStatusRequestFails() async {
        let cache = TestCacheClient()
        let conversationsAPI = ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([]))
        let ingestionAPI = makeIngestionAPIForAttachmentPollingTest()
        let viewModel = makeViewModel(
            api: conversationsAPI,
            cache: cache,
            ingestionAPI: ingestionAPI,
            attachmentPollingInitialDelayNanoseconds: 0,
            attachmentPollingIntervalNanoseconds: 0
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
        await waitForAttachmentPolling {
            viewModel.attachments.first(where: { $0.id == "attachment-1" })?.status == .failed
        }

        let attachment = viewModel.attachments.first(where: { $0.id == "attachment-1" })
        XCTAssertEqual(attachment?.status, .failed)
        XCTAssertEqual(attachment?.stage, "failed")
    }

    func testStartAttachmentPollingRemovesAttachmentWhenStatusIsCanceled() async {
        let cache = TestCacheClient()
        let conversationsAPI = ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([]))
        let canceledMetaResponse = """
        {
          "file": {
            "id": "file-1",
            "filename_original": "report.pdf",
            "path": null,
            "mime_original": "application/pdf",
            "size_bytes": 1,
            "sha256": null,
            "pinned": null,
            "pinned_order": null,
            "category": null,
            "source_url": null,
            "source_metadata": null,
            "created_at": "2026-01-01T00:00:00Z",
            "updated_at": null,
            "deleted_at": null
          },
          "job": {
            "status": "canceled",
            "stage": "canceled",
            "error_code": null,
            "error_message": null,
            "user_message": null,
            "progress": null,
            "attempts": 0,
            "updated_at": null
          },
          "derivatives": [],
          "recommended_viewer": null
        }
        """
        let ingestionAPI = makeIngestionAPIForAttachmentPollingTest(
            statusCode: 200,
            responseBody: canceledMetaResponse
        )
        let viewModel = makeViewModel(
            api: conversationsAPI,
            cache: cache,
            ingestionAPI: ingestionAPI,
            attachmentPollingInitialDelayNanoseconds: 0,
            attachmentPollingIntervalNanoseconds: 0
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
        await waitForAttachmentPolling {
            viewModel.attachments.isEmpty
        }

        XCTAssertTrue(viewModel.attachments.isEmpty)
        XCTAssertFalse(viewModel.hasPendingAttachments)
        XCTAssertTrue(viewModel.pendingAttachments.isEmpty)
    }

    func testCancelAttachmentRemovesAttachmentAndCallsCancelEndpoint() async {
        let cache = TestCacheClient()
        let conversationsAPI = ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([]))
        let cancelCalled = expectation(description: "Attachment cancel endpoint called")
        let ingestionAPI = makeIngestionAPIForAttachmentCancelTest { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("files/file-1/cancel") == true)
            cancelCalled.fulfill()
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
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

        viewModel.cancelAttachment(id: "attachment-1")

        XCTAssertTrue(viewModel.attachments.isEmpty)
        XCTAssertFalse(viewModel.hasPendingAttachments)
        await fulfillment(of: [cancelCalled], timeout: 1.0)
    }

}

extension ChatViewModelTests {
    func waitForAttachmentPolling(
        timeoutNanoseconds: UInt64 = 500_000_000,
        pollNanoseconds: UInt64 = 10_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let started = DispatchTime.now().uptimeNanoseconds
        while !condition() {
            if DispatchTime.now().uptimeNanoseconds - started > timeoutNanoseconds {
                XCTFail("Attachment polling did not reach the expected state before timeout")
                return
            }
            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }
    }

    func makeTemporaryAttachmentURL(filename: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-\(filename)")
        try Data("test".utf8).write(to: url, options: .atomic)
        return url
    }
}
