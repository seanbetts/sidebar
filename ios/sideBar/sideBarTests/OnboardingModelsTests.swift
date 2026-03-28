import XCTest
@testable import sideBar

final class OnboardingModelsTests: XCTestCase {
    func testOnboardingStateDecodesFromBackendJSON() throws {
        let json = """
        {
            "status": "in_progress",
            "provider_ready": true,
            "intent": "notes",
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
        """.data(using: .utf8)!

        let state = try JSONDecoder().decode(OnboardingState.self, from: json)
        XCTAssertEqual(state.status, .inProgress)
        XCTAssertTrue(state.providerReady)
        XCTAssertEqual(state.intent, .notes)
        XCTAssertEqual(state.milestones.providerConnected, "2026-03-28T10:00:00Z")
        XCTAssertNil(state.milestones.firstOutcomeCompleted)
        XCTAssertEqual(state.permissions.location, .notAsked)
    }

    func testOnboardingStateDecodesDefaults() throws {
        let json = """
        {
            "status": "not_started",
            "provider_ready": false,
            "intent": null,
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
        """.data(using: .utf8)!

        let state = try JSONDecoder().decode(OnboardingState.self, from: json)
        XCTAssertEqual(state.status, .notStarted)
        XCTAssertFalse(state.providerReady)
        XCTAssertNil(state.intent)
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
