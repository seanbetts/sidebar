import XCTest
import sideBarShared
@testable import sideBar

extension ChatViewModelTests {
    func testAcceptSoulCalibrationNameStartsHiddenKickoffInNewConversation() async throws {
        let cache = TestCacheClient()
        let onboardingAPI = MockOnboardingAPI()
        let streamClient = BlockingChatStreamClient()
        let created = Conversation(
            id: "conv-kickoff",
            title: "New Chat",
            titleGenerated: false,
            createdAt: "2026-04-04T10:00:00Z",
            updatedAt: "2026-04-04T10:00:00Z",
            messageCount: 0,
            firstMessage: nil,
            isArchived: nil
        )
        onboardingAPI.acceptCalibrationNameResult = .success(
            completedSoulCalibrationResponse()
        )
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(
                listResult: .success([]),
                createResult: .success(created)
            ),
            cache: cache,
            onboardingAPI: onboardingAPI,
            streamClient: streamClient
        )
        viewModel.syncSoulCalibration(
            from: awaitingNameAcceptanceSoulCalibrationState(proposedName: "Voss")
        )

        await viewModel.acceptSoulCalibrationName()

        let startedKickoff = await waitForStreamingFailureCondition {
            streamClient.lastRequest != nil && viewModel.messages.count == 1
        }

        XCTAssertTrue(startedKickoff)
        let kickoffRequest = try XCTUnwrap(streamClient.lastRequest)
        XCTAssertEqual(viewModel.selectedConversationId, created.id)
        XCTAssertEqual(kickoffRequest.conversationId, created.id)
        XCTAssertEqual(kickoffRequest.messageVisibility, .hidden)
        XCTAssertTrue(kickoffRequest.message.contains("Introduce yourself"))
        XCTAssertTrue(kickoffRequest.message.contains("Explore sideBar"))
        XCTAssertEqual(viewModel.messages.count, 1)
        XCTAssertEqual(viewModel.messages.first?.role, .assistant)
        XCTAssertTrue(viewModel.messages.first?.content.isEmpty == true)
        XCTAssertNil(viewModel.soulCalibrationState)
        XCTAssertFalse(viewModel.isSubmittingSoulCalibration)

        streamClient.release()
    }

    func testAcceptSoulCalibrationNameStartsHiddenKickoffInExistingConversation() async throws {
        let cache = TestCacheClient()
        let onboardingAPI = MockOnboardingAPI()
        let streamClient = BlockingChatStreamClient()
        onboardingAPI.acceptCalibrationNameResult = .success(
            completedSoulCalibrationResponse()
        )
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache,
            onboardingAPI: onboardingAPI,
            streamClient: streamClient
        )
        viewModel.selectedConversationId = "conv-existing"
        viewModel.messages = [
            Message(
                id: "assistant-existing",
                role: .assistant,
                content: "Earlier conversation",
                status: .complete,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2026-04-04T10:00:00Z",
                error: nil
            )
        ]
        viewModel.syncSoulCalibration(
            from: awaitingNameAcceptanceSoulCalibrationState(proposedName: "Riven")
        )

        await viewModel.acceptSoulCalibrationName()

        let startedKickoff = await waitForStreamingFailureCondition {
            streamClient.lastRequest != nil && viewModel.messages.count == 2
        }

        XCTAssertTrue(startedKickoff)
        let kickoffRequest = try XCTUnwrap(streamClient.lastRequest)
        XCTAssertEqual(kickoffRequest.conversationId, "conv-existing")
        XCTAssertEqual(kickoffRequest.messageVisibility, .hidden)
        XCTAssertEqual(viewModel.messages.last?.role, .assistant)
        XCTAssertTrue(viewModel.messages.last?.content.isEmpty == true)
        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertFalse(viewModel.isSubmittingSoulCalibration)

        streamClient.release()
    }

    func testAcceptSoulCalibrationNameIgnoresKickoffFailure() async {
        let cache = TestCacheClient()
        let onboardingAPI = MockOnboardingAPI()
        onboardingAPI.acceptCalibrationNameResult = .success(
            completedSoulCalibrationResponse()
        )
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(
                listResult: .success([]),
                createResult: .success(
                    Conversation(
                        id: "conv-kickoff",
                        title: "New Chat",
                        titleGenerated: false,
                        createdAt: "2026-04-04T10:00:00Z",
                        updatedAt: "2026-04-04T10:00:00Z",
                        messageCount: 0,
                        firstMessage: nil,
                        isArchived: nil
                    )
                )
            ),
            cache: cache,
            onboardingAPI: onboardingAPI,
            streamClient: FailingKickoffChatStreamClient()
        )
        viewModel.syncSoulCalibration(
            from: awaitingNameAcceptanceSoulCalibrationState(proposedName: "Calen")
        )

        await viewModel.acceptSoulCalibrationName()

        let finishedKickoffFailure = await waitForStreamingFailureCondition {
            viewModel.messages.isEmpty && viewModel.errorMessage == nil
        }

        XCTAssertTrue(finishedKickoffFailure)
        XCTAssertNil(viewModel.soulCalibrationState)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.messages.isEmpty)
    }

    func testAssistantInitiatedKickoffQueuesUntilCurrentStreamFinishes() async throws {
        let cache = TestCacheClient()
        let streamClient = BlockingChatStreamClient()
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache,
            streamClient: streamClient
        )
        viewModel.selectedConversationId = "conv-existing"
        viewModel.streamingConversationId = "conv-existing"
        viewModel.isStreaming = true
        viewModel.messages = [
            Message(
                id: "assistant-existing",
                role: .assistant,
                content: "Current streamed reply",
                status: .streaming,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2026-04-04T10:00:00Z",
                error: nil
            )
        ]
        viewModel.beginStreamingMessage(assistantMessageId: "assistant-existing")

        viewModel.enqueueAssistantInitiatedStream(
            ChatViewModel.AssistantInitiatedStreamOptions(
                instruction: "Introduce yourself briefly.",
                suppressErrors: true
            )
        )

        XCTAssertNil(streamClient.lastRequest)
        XCTAssertEqual(viewModel.pendingAssistantInitiatedStreams.count, 1)

        viewModel.finalizeStreaming(status: .complete)

        let startedQueuedKickoff = await waitForStreamingFailureCondition {
            streamClient.lastRequest != nil
                && viewModel.pendingAssistantInitiatedStreams.isEmpty
        }

        XCTAssertTrue(startedQueuedKickoff)
        XCTAssertEqual(streamClient.lastRequest?.conversationId, "conv-existing")
        XCTAssertEqual(streamClient.lastRequest?.messageVisibility, .hidden)

        streamClient.release()
    }
}

private func awaitingNameAcceptanceSoulCalibrationState(
    proposedName: String
) -> OnboardingState {
    OnboardingState(
        status: .inProgress,
        providerReady: true,
        currentOnboardingStep: .soulCalibration,
        isOnboardingComplete: false,
        intent: .chat,
        calibration: OnboardingCalibrationState(
            status: .awaitingNameAcceptance,
            currentPrompt: .tonePreferences,
            answers: OnboardingCalibrationAnswers(
                primaryGoal: "life_admin",
                workingRelationship: "take_initiative_with_me",
                tonePreferences: "warm,serious,concise,casual,supportive"
            ),
            proposedName: proposedName,
            completedAt: nil
        ),
        milestones: OnboardingMilestones(
            providerConnected: "2026-04-02T11:00:00Z",
            firstOutcomeCompleted: nil,
            profileBasicsSet: nil,
            communicationStyleSet: nil,
            secondaryTourSeen: nil
        ),
        permissions: OnboardingPermissions(location: .granted, notifications: .granted),
        lastPromptedAt: nil
    )
}

private func completedSoulCalibrationResponse() -> OnboardingCalibrationActionResponse {
    OnboardingCalibrationActionResponse(
        state: OnboardingState(
            status: .inProgress,
            providerReady: true,
            currentOnboardingStep: .featureDiscovery,
            isOnboardingComplete: false,
            intent: .chat,
            calibration: OnboardingCalibrationState(
                status: .completed,
                currentPrompt: .tonePreferences,
                answers: OnboardingCalibrationAnswers(
                    primaryGoal: "life_admin",
                    workingRelationship: "take_initiative_with_me",
                    tonePreferences: "warm,serious,concise,casual,supportive"
                ),
                proposedName: "Voss",
                completedAt: "2026-04-02T12:00:00Z"
            ),
            milestones: OnboardingMilestones(
                providerConnected: "2026-04-02T11:00:00Z",
                firstOutcomeCompleted: nil,
                profileBasicsSet: nil,
                communicationStyleSet: nil,
                secondaryTourSeen: nil
            ),
            permissions: OnboardingPermissions(location: .granted, notifications: .granted),
            lastPromptedAt: nil
        ),
        calibration: OnboardingCalibrationState(
            status: .completed,
            currentPrompt: .tonePreferences,
            answers: OnboardingCalibrationAnswers(
                primaryGoal: "life_admin",
                workingRelationship: "take_initiative_with_me",
                tonePreferences: "warm,serious,concise,casual,supportive"
            ),
            proposedName: "Voss",
            completedAt: "2026-04-02T12:00:00Z"
        ),
        assistantIdentity: AssistantIdentitySettings(
            name: "Voss",
            tone: "Warm, serious, concise, casual, supportive",
            values: "Helpful",
            boundaries: "Honest"
        ),
        assistantSoul: AssistantSoulSettings(
            purpose: "Help with life admin",
            operatingPrinciples: "Stay useful",
            adaptationPolicy: "Adjust initiative",
            successSignals: "User feels on top of things"
        ),
        confirmationText: "Voss it is."
    )
}

private final class FailingKickoffChatStreamClient: ChatStreamClient {
    weak var handler: ChatStreamEventHandler?

    func connect(request: ChatStreamRequest) async throws {
        _ = request
        throw APIClientError.requestFailed(503)
    }

    func disconnect() {
    }
}
