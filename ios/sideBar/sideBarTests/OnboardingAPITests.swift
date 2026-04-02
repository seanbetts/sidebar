import XCTest
@testable import sideBar

final class OnboardingAPITests: XCTestCase {
    func testOnboardingStateDecodesDerivedFieldsFromBackendJSON() throws {
        let json = """
        {
            "status": "in_progress",
            "provider_ready": true,
            "current_onboarding_step": "feature_discovery",
            "is_onboarding_complete": false,
            "intent": "notes",
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
    }

    func testOnboardingStateDecodesWithConvertFromSnakeCaseStrategy() throws {
        let json = """
        {
            "status": "completed",
            "provider_ready": false,
            "current_onboarding_step": "completed",
            "is_onboarding_complete": true,
            "intent": null,
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
        XCTAssertEqual(state.milestones.profileBasicsSet, "2026-03-30T12:56:27Z")
    }
}

private extension String {
    var utf8Data: Data {
        Data(utf8)
    }
}
