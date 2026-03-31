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
}

private extension String {
    var utf8Data: Data {
        Data(utf8)
    }
}
