import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class ChatRetryBehaviorTests: XCTestCase {
    func testLatestFailedAssistantMessageIsRetryEligible() async {
        let viewModel = makeStreamingFailureViewModel(
            api: StubConversationsAPI(),
            cache: TestCacheClient(),
            streamClient: SuccessfulChatStreamClient()
        )

        seedRetryableFailure(on: viewModel)

        XCTAssertEqual(viewModel.latestRetryableAssistantMessageID, "assistant-failed")
        XCTAssertTrue(viewModel.canRetryMessage(id: "assistant-failed"))
    }

    func testRetryLatestFailedTurnReplacesFailedAssistantWithNewStreamingMessage() async {
        let streamClient = BlockingChatStreamClient()
        let viewModel = makeStreamingFailureViewModel(
            api: StubConversationsAPI(),
            cache: TestCacheClient(),
            streamClient: streamClient
        )

        seedRetryableFailure(on: viewModel)

        async let retryTask = viewModel.retryLatestFailedTurn()

        let appended = await waitForStreamingFailureCondition {
            viewModel.messages.map(\.role) == [.user, .assistant]
                && viewModel.messages.last?.status == .streaming
                && viewModel.messages.last?.id != "assistant-failed"
        }

        XCTAssertTrue(appended)
        streamClient.release()
        await retryTask
    }

    func testRetryPersistsConversationSnapshotWithoutOriginalFailedAssistantMessage() async {
        let cache = TestCacheClient()
        let streamClient = BlockingChatStreamClient()
        let viewModel = makeStreamingFailureViewModel(
            api: StubConversationsAPI(),
            cache: cache,
            streamClient: streamClient
        )

        seedRetryableFailure(on: viewModel)

        async let retryTask = viewModel.retryLatestFailedTurn()

        let updated = await waitForStreamingFailureCondition {
            guard let detail = viewModel.chatStore.conversationDetails["conv-1"] else {
                return false
            }
            return detail.messages.count == 2
                && detail.messages.last?.status == .streaming
                && detail.messages.contains(where: { $0.id == "assistant-failed" }) == false
        }

        XCTAssertTrue(updated)
        let cached: [Message]? = cache.get(key: CacheKeys.conversationMessages(id: "conv-1"))
        XCTAssertEqual(cached?.count, 2)
        XCTAssertEqual(cached?.first?.id, "user-1")
        XCTAssertNotEqual(cached?.last?.id, "assistant-failed")
        XCTAssertEqual(cached?.last?.status, .streaming)

        streamClient.release()
        await retryTask
    }

    func testRetryLatestFailedTurnReusesCapturedOriginalRequestPayload() async {
        let streamClient = RecordingChatStreamClient()
        let viewModel = makeStreamingFailureViewModel(
            api: StubConversationsAPI(),
            cache: TestCacheClient(),
            streamClient: streamClient
        )

        seedRetryableFailure(
            on: viewModel,
            requestText: "Original question",
            attachments: [.fixture(id: "attachment-1")],
            openContext: ["selection": AnyCodable("captured")],
            location: "London, UK",
            locationLevels: ["country": "UK", "city": "London"],
            weather: ["condition": AnyCodable("rain")],
            timezone: "Europe/London"
        )

        await viewModel.retryLatestFailedTurn()

        XCTAssertEqual(streamClient.lastRequest?.message, "Original question")
        XCTAssertEqual(streamClient.lastRequest?.attachments?.map(\.fileId), ["attachment-1"])
        XCTAssertEqual(streamClient.lastRequest?.currentTimezone, "Europe/London")
        XCTAssertEqual(streamClient.lastRequest?.currentLocation, "London, UK")
        XCTAssertEqual(streamClient.lastRequest?.currentLocationLevels?["city"], "London")
        XCTAssertEqual(
            streamClient.lastRequest?.openContext?["selection"]?.value as? String,
            "captured"
        )
        XCTAssertEqual(
            streamClient.lastRequest?.currentWeather?["condition"]?.value as? String,
            "rain"
        )
    }

    func testSendMessageReplacesPreviousRetrySource() async {
        let viewModel = makeStreamingFailureViewModel(
            api: StubConversationsAPI(),
            cache: TestCacheClient(),
            streamClient: CompletingChatStreamClient(responseText: "New answer")
        )

        seedRetryableFailure(on: viewModel)

        await viewModel.sendMessage(text: "A newer question")

        XCTAssertFalse(viewModel.canRetryMessage(id: "assistant-failed"))
    }

    func testRetryLatestFailedTurnDoesNotStartDuplicateReplayWhenAlreadyRetrying() async {
        let streamClient = BlockingChatStreamClient()
        let viewModel = makeStreamingFailureViewModel(
            api: StubConversationsAPI(),
            cache: TestCacheClient(),
            streamClient: streamClient
        )

        seedRetryableFailure(on: viewModel)

        async let firstRetry = viewModel.retryLatestFailedTurn()
        let retryStarted = await waitForStreamingFailureCondition {
            streamClient.connectCallCount == 1
        }
        XCTAssertTrue(retryStarted)
        let inFlightAssistantMessageID = viewModel.retryInFlightAssistantMessageID
        let replayAssistantMessageID = viewModel.latestRetrySource?.assistantMessageID
        let messageCount = viewModel.messages.count

        async let secondRetry = viewModel.retryLatestFailedTurn()
        await settleStreamingFailureAsyncWork()

        XCTAssertEqual(viewModel.retryInFlightAssistantMessageID, inFlightAssistantMessageID)
        XCTAssertEqual(viewModel.latestRetrySource?.assistantMessageID, replayAssistantMessageID)
        XCTAssertEqual(viewModel.messages.count, messageCount)
        streamClient.release()
        await firstRetry
        await secondRetry

        XCTAssertEqual(streamClient.connectCallCount, 1)
    }

    func testRetryClearsRetryInFlightAfterTerminalFailure() async throws {
        let viewModel = makeStreamingFailureViewModel(
            api: StubConversationsAPI(),
            cache: TestCacheClient(),
            streamClient: FailingChatStreamClient(error: URLError(.timedOut))
        )

        seedRetryableFailure(on: viewModel)

        await viewModel.retryLatestFailedTurn()

        let newestFailedID = try XCTUnwrap(viewModel.messages.last?.id)
        XCTAssertNil(viewModel.retryInFlightAssistantMessageID)
        XCTAssertEqual(viewModel.latestRetryableAssistantMessageID, newestFailedID)
        XCTAssertFalse(viewModel.canRetryMessage(id: "assistant-failed"))
        XCTAssertTrue(viewModel.canRetryMessage(id: newestFailedID))
    }

    func testCancelledRetryRestoresLatestFailedAssistantEligibility() async {
        let streamClient = SleepingChatStreamClient()
        let viewModel = makeStreamingFailureViewModel(
            api: StubConversationsAPI(),
            cache: TestCacheClient(),
            streamClient: streamClient
        )

        seedRetryableFailure(on: viewModel)

        let retryTask = Task { await viewModel.retryLatestFailedTurn() }
        let retryStarted = await waitForStreamingFailureCondition {
            streamClient.connectCallCount == 1 && viewModel.retryInFlightAssistantMessageID == "assistant-failed"
        }
        XCTAssertTrue(retryStarted)

        retryTask.cancel()
        await retryTask.value

        XCTAssertEqual(viewModel.messages.map(\.id), ["user-1", "assistant-failed"])
        XCTAssertFalse(viewModel.messages.contains(where: { $0.status == .streaming }))
        XCTAssertNil(viewModel.currentStreamMessageId)
        XCTAssertNil(viewModel.retryInFlightAssistantMessageID)
        XCTAssertEqual(viewModel.latestRetrySource?.assistantMessageID, "assistant-failed")
        XCTAssertEqual(viewModel.latestRetryableAssistantMessageID, "assistant-failed")
        XCTAssertTrue(viewModel.canRetryMessage(id: "assistant-failed"))
    }

    func testStopStreamDuringRetryRestoresLatestFailedAssistantEligibility() async {
        let streamClient = BlockingChatStreamClient()
        let viewModel = makeStreamingFailureViewModel(
            api: StubConversationsAPI(),
            cache: TestCacheClient(),
            streamClient: streamClient
        )

        seedRetryableFailure(on: viewModel)

        let retryTask = Task { await viewModel.retryLatestFailedTurn() }
        let retryStarted = await waitForStreamingFailureCondition {
            streamClient.connectCallCount == 1 && viewModel.retryInFlightAssistantMessageID == "assistant-failed"
        }
        XCTAssertTrue(retryStarted)

        viewModel.stopStream()
        await retryTask.value

        XCTAssertEqual(viewModel.messages.map(\.id), ["user-1", "assistant-failed"])
        XCTAssertFalse(viewModel.messages.contains(where: { $0.status == .streaming }))
        XCTAssertNil(viewModel.currentStreamMessageId)
        XCTAssertNil(viewModel.retryInFlightAssistantMessageID)
        XCTAssertEqual(viewModel.latestRetrySource?.assistantMessageID, "assistant-failed")
        XCTAssertEqual(viewModel.latestRetryableAssistantMessageID, "assistant-failed")
        XCTAssertTrue(viewModel.canRetryMessage(id: "assistant-failed"))
    }

    func testRetryClearsRetryInFlightAfterSuccessfulCompletion() async {
        let viewModel = makeStreamingFailureViewModel(
            api: StubConversationsAPI(),
            cache: TestCacheClient(),
            streamClient: CompletingChatStreamClient(responseText: "Recovered answer")
        )

        seedRetryableFailure(on: viewModel)

        await viewModel.retryLatestFailedTurn()

        XCTAssertNil(viewModel.retryInFlightAssistantMessageID)
        XCTAssertFalse(viewModel.canRetryMessage(id: "assistant-failed"))
    }

    func testRetryEmptyResponseFailureRemainsVisibleAndRetryable() async throws {
        let viewModel = makeStreamingFailureViewModel(
            api: StubConversationsAPI(),
            cache: TestCacheClient(),
            streamClient: CompletingChatStreamClient()
        )

        seedRetryableFailure(on: viewModel)

        await viewModel.retryLatestFailedTurn()

        XCTAssertEqual(viewModel.messages.count, 2)
        let latestAssistantMessage = try XCTUnwrap(viewModel.messages.last)
        XCTAssertEqual(latestAssistantMessage.role, .assistant)
        XCTAssertEqual(latestAssistantMessage.status, .error)
        XCTAssertEqual(
            latestAssistantMessage.error,
            "The AI provider returned an empty response. Please try again."
        )
        XCTAssertEqual(viewModel.latestRetryableAssistantMessageID, latestAssistantMessage.id)
        XCTAssertFalse(viewModel.canRetryMessage(id: "assistant-failed"))
        XCTAssertTrue(viewModel.canRetryMessage(id: latestAssistantMessage.id))
    }

    func testDeleteConversationFailureRestoresRetryState() async {
        let viewModel = makeStreamingFailureViewModel(
            api: StubConversationsAPI(deleteResult: .failure(StreamFailureError.forced)),
            cache: TestCacheClient(),
            streamClient: SuccessfulChatStreamClient()
        )

        seedRetryableFailure(on: viewModel)

        await viewModel.deleteConversation(id: "conv-1")

        XCTAssertEqual(viewModel.selectedConversationId, "conv-1")
        XCTAssertEqual(viewModel.messages.map(\.id), ["user-1", "assistant-failed"])
        XCTAssertEqual(viewModel.latestRetrySource?.assistantMessageID, "assistant-failed")
        XCTAssertEqual(viewModel.latestRetryableAssistantMessageID, "assistant-failed")
        XCTAssertTrue(viewModel.canRetryMessage(id: "assistant-failed"))
    }

    func testRetryClearsRetryInFlightWhenReplaySourceIsStale() async {
        let viewModel = makeStreamingFailureViewModel(
            api: StubConversationsAPI(),
            cache: TestCacheClient(),
            streamClient: RecordingChatStreamClient()
        )

        seedRetryableFailure(on: viewModel)
        invalidateRetrySourceForTesting(on: viewModel)

        await viewModel.retryLatestFailedTurn()

        XCTAssertNil(viewModel.retryInFlightAssistantMessageID)
        XCTAssertFalse(viewModel.canRetryMessage(id: "assistant-failed"))
        XCTAssertEqual(viewModel.messages.map(\.role), [.user, .assistant])
    }
}
