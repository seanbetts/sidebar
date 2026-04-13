import XCTest
@testable import sideBar

@MainActor
final class OnboardingModelsTests: XCTestCase {
    func testPrimaryProviderExposesOnboardingLogoAssetNames() {
        XCTAssertEqual(AIPrimaryProvider.anthropic.onboardingLogoAssetName, "ProviderAnthropicLogo")
        XCTAssertEqual(AIPrimaryProvider.openai.onboardingLogoAssetName, "ProviderOpenAILogo")
        XCTAssertEqual(AIPrimaryProvider.google.onboardingLogoAssetName, "ProviderGoogleLogo")
    }

    func testPrimaryProviderExposesAPIKeySetupURLs() {
        XCTAssertEqual(
            AIPrimaryProvider.anthropic.apiKeySetupURL?.absoluteString,
            "https://docs.trysidebar.ai/manual/api-keys#anthropic"
        )
        XCTAssertEqual(
            AIPrimaryProvider.openai.apiKeySetupURL?.absoluteString,
            "https://docs.trysidebar.ai/manual/api-keys#openai"
        )
        XCTAssertEqual(
            AIPrimaryProvider.google.apiKeySetupURL?.absoluteString,
            "https://docs.trysidebar.ai/manual/api-keys#google"
        )
    }

    func testOnboardingStateDecodesFromBackendJSON() throws {
        let json = """
        {
            "status": "in_progress",
            "provider_ready": true,
            "current_onboarding_step": "feature_discovery",
            "is_onboarding_complete": false,
            "intent": "notes",
            "calibration": {
                "status": "completed",
                "current_prompt": "tone_preferences",
                "answers": {
                    "primary_goal": "life_admin",
                    "working_relationship": "coach",
                    "tone_preferences": "warm,direct"
                },
                "proposed_name": "Navigator",
                "completed_at": "2026-03-28T09:59:00Z"
            },
            "milestones": {
                "provider_connected": "2026-03-28T10:00:00Z",
                "first_outcome_completed": null,
                "profile_basics_set": "2026-03-28T09:55:00Z",
                "communication_style_set": null,
                "secondary_tour_seen": null
            },
            "permissions": {
                "location": "not_asked",
                "notifications": "not_asked"
            },
            "last_prompted_at": null
        }
        """.utf8Data

        let state = try JSONDecoder().decode(OnboardingState.self, from: json)
        XCTAssertEqual(state.status, .inProgress)
        XCTAssertTrue(state.providerReady)
        XCTAssertEqual(state.currentOnboardingStep, .featureDiscovery)
        XCTAssertFalse(state.isOnboardingComplete)
        XCTAssertEqual(state.intent, .notes)
        XCTAssertEqual(state.calibration.status, .completed)
        XCTAssertEqual(state.calibration.currentPrompt, .tonePreferences)
        XCTAssertEqual(state.calibration.proposedName, "Navigator")
        XCTAssertEqual(state.milestones.providerConnected, "2026-03-28T10:00:00Z")
        XCTAssertNil(state.milestones.firstOutcomeCompleted)
        XCTAssertEqual(state.permissions.location, .notAsked)
    }

    func testOnboardingStateDecodesDefaults() throws {
        let json = """
        {
            "status": "not_started",
            "provider_ready": false,
            "current_onboarding_step": "phase1_wizard",
            "is_onboarding_complete": false,
            "intent": null,
            "calibration": {
                "status": "not_started",
                "current_prompt": "primary_goal",
                "answers": {
                    "primary_goal": null,
                    "working_relationship": null,
                    "tone_preferences": null
                },
                "proposed_name": null,
                "completed_at": null
            },
            "milestones": {
                "provider_connected": null,
                "first_outcome_completed": null,
                "profile_basics_set": null,
                "communication_style_set": null,
                "secondary_tour_seen": null
            },
            "permissions": {
                "location": "not_asked",
                "notifications": "not_asked"
            },
            "last_prompted_at": null
        }
        """.utf8Data

        let state = try JSONDecoder().decode(OnboardingState.self, from: json)
        XCTAssertEqual(state.status, .notStarted)
        XCTAssertFalse(state.providerReady)
        XCTAssertEqual(state.currentOnboardingStep, .phase1Wizard)
        XCTAssertEqual(state.calibration.currentPrompt, .primaryGoal)
        XCTAssertFalse(state.isOnboardingComplete)
        XCTAssertNil(state.intent)
    }

    func testOnboardingStateDecodesSoulCalibrationStepAndAnswers() throws {
        let json = """
        {
            "status": "in_progress",
            "provider_ready": true,
            "current_onboarding_step": "soul_calibration",
            "is_onboarding_complete": false,
            "intent": "chat",
            "calibration": {
                "status": "awaiting_name_acceptance",
                "current_prompt": "tone_preferences",
                "answers": {
                    "primary_goal": "life_admin",
                    "working_relationship": "coach",
                    "tone_preferences": "warm,serious,concise,casual,supportive"
                },
                "proposed_name": "Navigator",
                "completed_at": null
            },
            "milestones": {
                "provider_connected": "2026-04-02T09:00:00Z",
                "first_outcome_completed": null,
                "profile_basics_set": null,
                "communication_style_set": null,
                "secondary_tour_seen": null
            },
            "permissions": {
                "location": "not_asked",
                "notifications": "not_asked"
            },
            "last_prompted_at": null
        }
        """.utf8Data

        let state = try JSONDecoder().decode(OnboardingState.self, from: json)

        XCTAssertEqual(state.currentOnboardingStep, .soulCalibration)
        XCTAssertEqual(state.calibration.status, .awaitingNameAcceptance)
        XCTAssertEqual(state.calibration.currentPrompt, .tonePreferences)
        XCTAssertEqual(state.calibration.answers.primaryGoal, "life_admin")
        XCTAssertEqual(
            state.calibration.answers.tonePreferences,
            "warm,serious,concise,casual,supportive"
        )
        XCTAssertEqual(state.calibration.proposedName, "Navigator")
    }

    func testOnboardingUpdateEncodesPartialPatch() throws {
        let update = OnboardingUpdate(status: .inProgress)
        let data = try JSONEncoder().encode(update)
        let dict = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(dict["status"] as? String, "in_progress")
        XCTAssertNil(dict["intent"])
    }

    func testOnboardingMilestoneUpdateEncodes() throws {
        let update = OnboardingUpdate(
            milestones: OnboardingMilestonesUpdate(
                profileBasicsSet: "2026-03-28T10:00:00Z"
            )
        )
        let data = try JSONEncoder().encode(update)
        let dict = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let milestones = try XCTUnwrap(dict["milestones"] as? [String: Any])

        XCTAssertEqual(milestones["profile_basics_set"] as? String, "2026-03-28T10:00:00Z")
        XCTAssertNil(milestones["provider_connected"])
    }
}

private extension String {
    var utf8Data: Data {
        Data(utf8)
    }
}
