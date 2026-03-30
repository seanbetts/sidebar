import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class OnboardingViewModelProfileSyncTests: XCTestCase {
    private func makeUserDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: #filePath)!
        defaults.removePersistentDomain(forName: #filePath)
        return defaults
    }

    func testSaveProfilePublishesUpdatedSettingsResponse() async {
        let settingsAPI = OnboardingMockSettingsAPI()
        let publishedSettings = expectation(description: "Published settings response")
        var capturedSettings: UserSettings?

        let viewModel = OnboardingViewModel(
            authSession: MockAuthSessionForOnboarding(),
            onboardingAPI: MockOnboardingAPI(),
            settingsAPI: settingsAPI,
            onSettingsUpdated: { settings in
                capturedSettings = settings
                publishedSettings.fulfill()
            },
            userDefaults: makeUserDefaults()
        )
        viewModel.currentStep = OnboardingStep.profile
        viewModel.displayName = "Sean"

        await viewModel.saveProfile()

        await fulfillment(of: [publishedSettings], timeout: 1.0)
        XCTAssertEqual(capturedSettings?.name, "Sean")
    }
}
