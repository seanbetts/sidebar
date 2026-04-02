import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class OnboardingAPITests: XCTestCase {
    private var router: ScopedURLProtocolRouter!

    override func setUp() {
        super.setUp()
        router = ScopedURLProtocolRouter()
    }

    override func tearDown() {
        router.invalidate()
        router = nil
        super.tearDown()
    }

    func testOnboardingStateDecodesDerivedFieldsFromBackendJSON() throws {
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
                "completed_at": "2026-04-02T09:10:00Z"
            },
            "milestones": {
                "provider_connected": "2026-03-28T10:00:00Z",
                "first_outcome_completed": null,
                "profile_basics_set": "2026-03-28T09:55:00Z",
                "communication_style_set": null,
                "secondary_tour_seen": null
            },
            "permissions": {
                "location": "granted",
                "notifications": "granted"
            },
            "last_prompted_at": null
        }
        """.utf8Data

        let state = try JSONDecoder().decode(OnboardingState.self, from: json)

        XCTAssertEqual(state.currentOnboardingStep, .featureDiscovery)
        XCTAssertFalse(state.isOnboardingComplete)
        XCTAssertEqual(state.calibration.status, .completed)
        XCTAssertEqual(state.calibration.proposedName, "Navigator")
    }

    func testOnboardingStateDecodesWithConvertFromSnakeCaseStrategy() throws {
        let json = """
        {
            "status": "completed",
            "provider_ready": false,
            "current_onboarding_step": "completed",
            "is_onboarding_complete": true,
            "intent": null,
            "calibration": {
                "status": "completed",
                "current_prompt": "tone_preferences",
                "answers": {
                    "primary_goal": "life_admin",
                    "working_relationship": "coach",
                    "tone_preferences": "warm,direct"
                },
                "proposed_name": "Navigator",
                "completed_at": "2026-03-30T12:56:27Z"
            },
            "milestones": {
                "provider_connected": null,
                "first_outcome_completed": null,
                "profile_basics_set": "2026-03-30T12:56:27Z",
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

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let state = try decoder.decode(OnboardingState.self, from: json)

        XCTAssertFalse(state.providerReady)
        XCTAssertEqual(state.currentOnboardingStep, .completed)
        XCTAssertTrue(state.isOnboardingComplete)
        XCTAssertEqual(state.calibration.completedAt, "2026-03-30T12:56:27Z")
        XCTAssertEqual(state.milestones.profileBasicsSet, "2026-03-30T12:56:27Z")
    }

    func testSubmitCalibrationAnswerUsesPostWithPromptAndAnswerBody() async throws {
        let api = OnboardingAPI(client: makeClient())
        router.setHandler { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(
                request.url?.absoluteString.contains("onboarding/calibration/respond") == true
            )
            let bodyData = try XCTUnwrap(request.httpBodyData())
            let body = try XCTUnwrap(
                JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            )
            XCTAssertEqual(body["prompt"] as? String, "primary_goal")
            XCTAssertEqual(body["answer"] as? String, "life_admin")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(self.makeCalibrationResponseJSON().utf8))
        }

        let response = try await api.submitCalibrationAnswer(
            .primaryGoal,
            answer: .singleChoice("life_admin")
        )

        XCTAssertEqual(response.state.currentOnboardingStep, .soulCalibration)
        XCTAssertEqual(response.calibration.currentPrompt, .tonePreferences)
        XCTAssertEqual(response.assistantIdentity?.name, "Navigator")
        XCTAssertEqual(response.assistantSoul?.purpose, "Help with life admin.")
    }

    func testRegenerateCalibrationNameUsesPostWithEmptyBody() async throws {
        let api = OnboardingAPI(client: makeClient())
        router.setHandler { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(
                request.url?.absoluteString.contains("onboarding/calibration/name/regenerate") == true
            )
            let bodyData = try XCTUnwrap(request.httpBodyData())
            let body = try XCTUnwrap(
                JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            )
            XCTAssertTrue(body.isEmpty)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(self.makeCalibrationResponseJSON().utf8))
        }

        let response = try await api.regenerateCalibrationName()

        XCTAssertEqual(response.assistantIdentity?.name, "Navigator")
        XCTAssertEqual(response.confirmationText, "Navigator is ready.")
    }

    func testAcceptCalibrationNameUsesPostWithEmptyBody() async throws {
        let api = OnboardingAPI(client: makeClient())
        router.setHandler { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(
                request.url?.absoluteString.contains("onboarding/calibration/name/accept") == true
            )
            let bodyData = try XCTUnwrap(request.httpBodyData())
            let body = try XCTUnwrap(
                JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            )
            XCTAssertTrue(body.isEmpty)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(self.makeCompletedCalibrationResponseJSON().utf8))
        }

        let response = try await api.acceptCalibrationName()

        XCTAssertEqual(response.state.currentOnboardingStep, .featureDiscovery)
        XCTAssertEqual(response.calibration.status, .completed)
        XCTAssertEqual(response.calibration.proposedName, "Navigator")
    }

    private func makeClient(router: ScopedURLProtocolRouter? = nil) -> APIClient {
        guard let resolvedRouter = router ?? self.router else {
            fatalError("Expected scoped router to be configured before creating APIClient")
        }
        let config = APIClientConfig(
            baseUrl: resolvedRouter.baseURL,
            accessTokenProvider: { nil }
        )
        return APIClient(config: config, session: resolvedRouter.makeSession())
    }

    private func makeCalibrationResponseJSON() -> String {
        """
        {
          "state": {
            "status": "in_progress",
            "provider_ready": true,
            "current_onboarding_step": "soul_calibration",
            "is_onboarding_complete": false,
            "intent": "notes",
            "calibration": {
              "status": "awaiting_name_acceptance",
              "current_prompt": "tone_preferences",
              "answers": {
                "primary_goal": "life_admin",
                "working_relationship": "coach",
                "tone_preferences": "warm,direct"
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
          },
          "calibration": {
            "status": "awaiting_name_acceptance",
            "current_prompt": "tone_preferences",
            "answers": {
              "primary_goal": "life_admin",
              "working_relationship": "coach",
              "tone_preferences": "warm,direct"
            },
            "proposed_name": "Navigator",
            "completed_at": null
          },
          "assistant_identity": {
            "name": "Navigator",
            "tone": "Warm and direct.",
            "boundaries": "Stay grounded in the user's goals.",
            "values": "Clarity and momentum."
          },
          "assistant_soul": {
            "purpose": "Help with life admin.",
            "operating_principles": "Coach with momentum.",
            "adaptation_policy": "Adapt from repeated feedback.",
            "success_signals": "More clarity and less drift."
          },
          "confirmation_text": "Navigator is ready."
        }
        """
    }

    private func makeCompletedCalibrationResponseJSON() -> String {
        """
        {
          "state": {
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
              "completed_at": "2026-04-02T09:12:00Z"
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
          },
          "calibration": {
            "status": "completed",
            "current_prompt": "tone_preferences",
            "answers": {
              "primary_goal": "life_admin",
              "working_relationship": "coach",
              "tone_preferences": "warm,direct"
            },
            "proposed_name": "Navigator",
            "completed_at": "2026-04-02T09:12:00Z"
          },
          "assistant_identity": {
            "name": "Navigator",
            "tone": "Warm and direct.",
            "boundaries": "Stay grounded in the user's goals.",
            "values": "Clarity and momentum."
          },
          "assistant_soul": {
            "purpose": "Help with life admin.",
            "operating_principles": "Coach with momentum.",
            "adaptation_policy": "Adapt from repeated feedback.",
            "success_signals": "More clarity and less drift."
          },
          "confirmation_text": "Navigator is locked in."
        }
        """
    }
}

private extension String {
    var utf8Data: Data {
        Data(utf8)
    }
}
