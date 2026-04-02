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
            "Help me get started with notes in sideBar. Write me a short guided intro as a note to demonstrate how notes work."
        )
    }
}
