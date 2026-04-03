import XCTest
import sideBarShared
@testable import sideBar

extension ChatViewModelTests {
    func testSyncSoulCalibrationUsesCurrentOnboardingPrompt() {
        let cache = TestCacheClient()
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache
        )

        viewModel.syncSoulCalibration(
            from: soulCalibrationOnboardingState(
                currentPrompt: .primaryGoal,
                status: .inProgress
            )
        )

        XCTAssertEqual(viewModel.soulCalibrationState?.currentPrompt, .primaryGoal)
    }

    func testSubmitSoulCalibrationAnswerAdvancesPrompt() async throws {
        let cache = TestCacheClient()
        let onboardingAPI = MockOnboardingAPI()
        onboardingAPI.submitCalibrationAnswerResult = .success(
            OnboardingCalibrationActionResponse(
                state: soulCalibrationOnboardingState(
                    currentPrompt: .workingRelationship,
                    status: .inProgress,
                    primaryGoal: "life_admin"
                ),
                calibration: OnboardingCalibrationState(
                    status: .inProgress,
                    currentPrompt: .workingRelationship,
                    answers: OnboardingCalibrationAnswers(
                        primaryGoal: "life_admin",
                        workingRelationship: nil,
                        tonePreferences: nil
                    ),
                    proposedName: nil,
                    completedAt: nil
                ),
                assistantIdentity: nil,
                assistantSoul: nil,
                confirmationText: nil
            )
        )
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache,
            onboardingAPI: onboardingAPI
        )
        viewModel.syncSoulCalibration(
            from: soulCalibrationOnboardingState(
                currentPrompt: .primaryGoal,
                status: .inProgress
            )
        )

        await viewModel.submitSoulCalibrationAnswer(.singleChoice("life_admin"))

        XCTAssertEqual(onboardingAPI.submittedCalibrationAnswers.count, 1)
        XCTAssertEqual(onboardingAPI.submittedCalibrationAnswers.first?.prompt, .primaryGoal)
        XCTAssertEqual(viewModel.soulCalibrationState?.currentPrompt, .workingRelationship)
    }

    func testSubmitSoulCalibrationToneChoicesTransitionsToNameAcceptance() async throws {
        let cache = TestCacheClient()
        let onboardingAPI = MockOnboardingAPI()
        onboardingAPI.submitCalibrationAnswerResult = .success(
            OnboardingCalibrationActionResponse(
                state: soulCalibrationOnboardingState(
                    currentPrompt: .tonePreferences,
                    status: .awaitingNameAcceptance,
                    primaryGoal: "life_admin",
                    workingRelationship: "take_initiative_with_me",
                    tonePreferences: "warm,serious,concise,casual,supportive",
                    proposedName: "Navigator"
                ),
                calibration: OnboardingCalibrationState(
                    status: .awaitingNameAcceptance,
                    currentPrompt: .tonePreferences,
                    answers: OnboardingCalibrationAnswers(
                        primaryGoal: "life_admin",
                        workingRelationship: "take_initiative_with_me",
                        tonePreferences: "warm,serious,concise,casual,supportive"
                    ),
                    proposedName: "Navigator",
                    completedAt: nil
                ),
                assistantIdentity: AssistantIdentitySettings(
                    name: "Navigator",
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

        await viewModel.submitSoulCalibrationAnswer(
            .multipleChoice(["warm", "serious", "concise", "casual", "supportive"])
        )

        XCTAssertEqual(onboardingAPI.submittedCalibrationAnswers.first?.prompt, .tonePreferences)
        XCTAssertEqual(viewModel.soulCalibrationState?.status, .awaitingNameAcceptance)
        XCTAssertEqual(viewModel.soulCalibrationState?.proposedName, "Navigator")
    }

    func testSubmitSoulCalibrationAnswerUsesExplicitPromptWhenRevisitingEarlierStep() async throws {
        let cache = TestCacheClient()
        let onboardingAPI = MockOnboardingAPI()
        onboardingAPI.submitCalibrationAnswerResult = .success(
            OnboardingCalibrationActionResponse(
                state: soulCalibrationOnboardingState(
                    currentPrompt: .tonePreferences,
                    status: .inProgress,
                    primaryGoal: "life_admin",
                    workingRelationship: "take_initiative_with_me"
                ),
                calibration: OnboardingCalibrationState(
                    status: .inProgress,
                    currentPrompt: .tonePreferences,
                    answers: OnboardingCalibrationAnswers(
                        primaryGoal: "life_admin",
                        workingRelationship: "take_initiative_with_me",
                        tonePreferences: nil
                    ),
                    proposedName: nil,
                    completedAt: nil
                ),
                assistantIdentity: nil,
                assistantSoul: nil,
                confirmationText: "How should I sound when we work together?"
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
                workingRelationship: "keep_me_on_track",
                tonePreferences: "warm,serious,concise,casual,supportive"
            )
        )

        await viewModel.submitSoulCalibrationAnswer(
            prompt: .workingRelationship,
            .singleChoice("take_initiative_with_me")
        )

        XCTAssertEqual(onboardingAPI.submittedCalibrationAnswers.count, 1)
        XCTAssertEqual(
            onboardingAPI.submittedCalibrationAnswers.first?.prompt,
            .workingRelationship
        )
        XCTAssertEqual(
            onboardingAPI.submittedCalibrationAnswers.first?.answer,
            .singleChoice("take_initiative_with_me")
        )
    }

    func testSubmitSoulCalibrationAnswerQueuesOptimisticNextStepWhilePreviousStepIsInFlight() async throws {
        let cache = TestCacheClient()
        let onboardingAPI = DelayedOnboardingAPI()
        onboardingAPI.shouldSuspendSubmitUntilResumed = true
        onboardingAPI.submitCalibrationAnswerResults = queuedSoulCalibrationAnswerResults()
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: cache,
            onboardingAPI: onboardingAPI
        )
        viewModel.syncSoulCalibration(
            from: soulCalibrationOnboardingState(
                currentPrompt: .primaryGoal,
                status: .inProgress
            )
        )

        let firstSubmitStarted = expectation(description: "first calibration submit started")
        var didObserveFirstSubmitStart = false
        onboardingAPI.onSubmitStarted = {
            guard !didObserveFirstSubmitStart else {
                return
            }
            didObserveFirstSubmitStart = true
            firstSubmitStarted.fulfill()
        }

        let firstSubmit = Task {
            await viewModel.submitSoulCalibrationAnswer(
                prompt: .primaryGoal,
                .singleChoice("life_admin")
            )
        }
        await fulfillment(of: [firstSubmitStarted], timeout: 1.0)

        let secondSubmit = Task {
            await viewModel.submitSoulCalibrationAnswer(
                prompt: .workingRelationship,
                .singleChoice("keep_me_on_track")
            )
        }
        await Task.yield()
        onboardingAPI.shouldSuspendSubmitUntilResumed = false
        onboardingAPI.resumeSubmit()

        _ = await firstSubmit.value
        _ = await secondSubmit.value

        XCTAssertEqual(
            onboardingAPI.submittedCalibrationAnswers.map(\.prompt),
            [.primaryGoal, .workingRelationship]
        )
        XCTAssertEqual(viewModel.soulCalibrationState?.currentPrompt, .tonePreferences)
    }

    func testAcceptSoulCalibrationNameClearsStateAndAllowsDiscovery() async throws {
        let cache = TestCacheClient()
        let onboardingAPI = MockOnboardingAPI()
        onboardingAPI.acceptCalibrationNameResult = .success(
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
                        proposedName: "Navigator",
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
                    proposedName: "Navigator",
                    completedAt: "2026-04-02T12:00:00Z"
                ),
                assistantIdentity: AssistantIdentitySettings(
                    name: "Navigator",
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
                confirmationText: "Navigator it is."
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
                status: .awaitingNameAcceptance,
                primaryGoal: "life_admin",
                workingRelationship: "take_initiative_with_me",
                tonePreferences: "warm,serious,concise,casual,supportive",
                proposedName: "Navigator"
            )
        )

        await viewModel.acceptSoulCalibrationName()

        XCTAssertEqual(onboardingAPI.acceptCalibrationNameCallCount, 1)
        XCTAssertNil(viewModel.soulCalibrationState)
        XCTAssertTrue(viewModel.canShowFeatureDiscovery)
    }
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

private func queuedSoulCalibrationAnswerResults() -> [Result<OnboardingCalibrationActionResponse, Error>] {
    [
        .success(
            OnboardingCalibrationActionResponse(
                state: soulCalibrationOnboardingState(
                    currentPrompt: .workingRelationship,
                    status: .inProgress,
                    primaryGoal: "life_admin"
                ),
                calibration: OnboardingCalibrationState(
                    status: .inProgress,
                    currentPrompt: .workingRelationship,
                    answers: OnboardingCalibrationAnswers(
                        primaryGoal: "life_admin",
                        workingRelationship: nil,
                        tonePreferences: nil
                    ),
                    proposedName: nil,
                    completedAt: nil
                ),
                assistantIdentity: nil,
                assistantSoul: AssistantSoulSettings(
                    purpose: "Help with life admin",
                    operatingPrinciples: nil,
                    adaptationPolicy: nil,
                    successSignals: nil
                ),
                confirmationText: nil
            )
        ),
        .success(
            OnboardingCalibrationActionResponse(
                state: soulCalibrationOnboardingState(
                    currentPrompt: .tonePreferences,
                    status: .inProgress,
                    primaryGoal: "life_admin",
                    workingRelationship: "keep_me_on_track"
                ),
                calibration: OnboardingCalibrationState(
                    status: .inProgress,
                    currentPrompt: .tonePreferences,
                    answers: OnboardingCalibrationAnswers(
                        primaryGoal: "life_admin",
                        workingRelationship: "keep_me_on_track",
                        tonePreferences: nil
                    ),
                    proposedName: nil,
                    completedAt: nil
                ),
                assistantIdentity: nil,
                assistantSoul: AssistantSoulSettings(
                    purpose: "Help with life admin",
                    operatingPrinciples: "Keep momentum visible.",
                    adaptationPolicy: "Adapt to durable preferences.",
                    successSignals: "More follow-through."
                ),
                confirmationText: nil
            )
        )
    ]
}
