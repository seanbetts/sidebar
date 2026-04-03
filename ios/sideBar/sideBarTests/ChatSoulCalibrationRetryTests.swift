import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class ChatSoulCalibrationRetryTests: ChatViewModelTestCase {
    func testSubmitSoulCalibrationToneChoicesGeneratesNameAfterTransition() async throws {
        let cache = TestCacheClient()
        let onboardingAPI = MockOnboardingAPI()
        onboardingAPI.submitCalibrationAnswerResult = .success(awaitingNameResponse())
        onboardingAPI.regenerateCalibrationNameResult = .success(
            awaitingNameResponse(
                proposedName: "Navigator",
                name: "Navigator",
                confirmationText: "I think Navigator fits."
            )
        )
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache,
            onboardingAPI: onboardingAPI
        )
        viewModel.syncSoulCalibration(
            from: soulCalibrationOnboardingState(
                currentPrompt: .tonePreferences,
                status: .inProgress,
                primaryGoal: "life_admin",
                workingRelationship: "take_initiative_with_me"
            )
        )

        let answer = OnboardingCalibrationAnswer.multipleChoice([
            "warm", "serious", "concise", "casual", "supportive"
        ])
        await viewModel.submitSoulCalibrationAnswer(prompt: .tonePreferences, answer)

        XCTAssertEqual(onboardingAPI.submittedCalibrationAnswers.count, 1)
        XCTAssertEqual(onboardingAPI.regenerateCalibrationNameCallCount, 1)
        XCTAssertNil(viewModel.soulCalibrationErrorMessage)
        XCTAssertEqual(viewModel.soulCalibrationState?.status, .awaitingNameAcceptance)
        XCTAssertEqual(viewModel.soulCalibrationState?.proposedName, "Navigator")
    }

    func testSubmitSoulCalibrationToneChoicesLeavesNameStepRetryableWhenInitialGenerationFails() async throws {
        let cache = TestCacheClient()
        let onboardingAPI = MockOnboardingAPI()
        onboardingAPI.submitCalibrationAnswerResult = .success(awaitingNameResponse())
        onboardingAPI.regenerateCalibrationNameResult = .failure(URLError(.timedOut))
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache,
            onboardingAPI: onboardingAPI
        )
        viewModel.syncSoulCalibration(
            from: soulCalibrationOnboardingState(
                currentPrompt: .tonePreferences,
                status: .inProgress,
                primaryGoal: "life_admin",
                workingRelationship: "take_initiative_with_me"
            )
        )

        await viewModel.submitSoulCalibrationAnswer(
            prompt: .tonePreferences,
            .multipleChoice(["warm", "serious", "concise", "casual", "supportive"])
        )

        XCTAssertEqual(onboardingAPI.submittedCalibrationAnswers.count, 1)
        XCTAssertEqual(onboardingAPI.regenerateCalibrationNameCallCount, 1)
        XCTAssertEqual(viewModel.soulCalibrationState?.status, .awaitingNameAcceptance)
        XCTAssertNil(viewModel.soulCalibrationState?.proposedName)
        XCTAssertEqual(
            viewModel.soulCalibrationErrorMessage,
            "Server took too long to respond. Please try again."
        )
    }

    func testSubmitSoulCalibrationToneChoicesDoesNotAdvanceToNameWhenToneSaveFails() async throws {
        let cache = TestCacheClient()
        let onboardingAPI = MockOnboardingAPI()
        onboardingAPI.submitCalibrationAnswerResult = .failure(URLError(.timedOut))
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache,
            onboardingAPI: onboardingAPI
        )
        viewModel.syncSoulCalibration(
            from: soulCalibrationOnboardingState(
                currentPrompt: .tonePreferences,
                status: .inProgress,
                primaryGoal: "life_admin",
                workingRelationship: "take_initiative_with_me"
            )
        )

        await viewModel.submitSoulCalibrationAnswer(
            prompt: .tonePreferences,
            .multipleChoice(["warm", "serious", "concise", "casual", "supportive"])
        )

        XCTAssertEqual(onboardingAPI.submittedCalibrationAnswers.count, 1)
        XCTAssertEqual(onboardingAPI.regenerateCalibrationNameCallCount, 0)
        XCTAssertEqual(viewModel.soulCalibrationState?.status, .inProgress)
        XCTAssertEqual(viewModel.soulCalibrationState?.currentPrompt, .tonePreferences)
        XCTAssertNil(viewModel.soulCalibrationState?.proposedName)
        XCTAssertEqual(
            viewModel.soulCalibrationErrorMessage,
            "Server took too long to respond. Please try again."
        )
    }

    private func soulCalibrationOnboardingState(
        currentPrompt: OnboardingCalibrationPrompt,
        status: OnboardingCalibrationStatus,
        primaryGoal: String? = nil,
        workingRelationship: String? = nil,
        tonePreferences: String? = nil,
        proposedName: String? = nil
    ) -> OnboardingState {
        OnboardingState(
            status: .inProgress,
            providerReady: true,
            currentOnboardingStep: .soulCalibration,
            isOnboardingComplete: false,
            intent: .chat,
            calibration: OnboardingCalibrationState(
                status: status,
                currentPrompt: currentPrompt,
                answers: OnboardingCalibrationAnswers(
                    primaryGoal: primaryGoal,
                    workingRelationship: workingRelationship,
                    tonePreferences: tonePreferences
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

    private func awaitingNameResponse(
        proposedName: String? = nil,
        name: String? = nil,
        confirmationText: String? = nil
    ) -> OnboardingCalibrationActionResponse {
        OnboardingCalibrationActionResponse(
            state: soulCalibrationOnboardingState(
                currentPrompt: .tonePreferences,
                status: .awaitingNameAcceptance,
                primaryGoal: "life_admin",
                workingRelationship: "take_initiative_with_me",
                tonePreferences: "warm,serious,concise,casual,supportive",
                proposedName: proposedName
            ),
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
            assistantIdentity: AssistantIdentitySettings(
                name: name,
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
            confirmationText: confirmationText
        )
    }
}
