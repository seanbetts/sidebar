import XCTest
@testable import sideBar

final class OnboardingDiscoveryFeatureTests: XCTestCase {
    func testAllCasesExcludeChat() {
        XCTAssertEqual(
            OnboardingDiscoveryFeature.allCases,
            [.notes, .tasks, .websites, .files, .skills]
        )
    }

    func testNotesKickoffPromptRequestsGuidedIntroAsNote() {
        XCTAssertEqual(
            OnboardingDiscoveryFeature.notes.kickoffPrompt,
            "Help me get started with notes in sideBar. " +
                "Write me a short guided intro as a note to demonstrate how notes work, " +
                "showing off and explaining all the features."
        )
    }

    func testOtherKickoffPromptsMatchFeatureSpecificActions() {
        XCTAssertEqual(
            OnboardingDiscoveryFeature.tasks.kickoffPrompt,
            "Help me get started with Tasks in sideBar. Give me a short guided intro and create a simple task to show off all the features."
        )
        XCTAssertEqual(
            OnboardingDiscoveryFeature.websites.kickoffPrompt,
            "Help me get started with Websites in sideBar. " +
                "Give me a short guided intro and save " +
                "https://docs.trysidebar.ai/manual/introduction to show off all the features."
        )
        XCTAssertEqual(
            OnboardingDiscoveryFeature.files.kickoffPrompt,
            "Help me get started with Files in sideBar. Give me a short guided intro that covers all of the features."
        )
        XCTAssertEqual(
            OnboardingDiscoveryFeature.skills.kickoffPrompt,
            "Help me get started with Skills in sideBar. Give me a short guided intro and a summary of some of the best skills."
        )
    }
}
