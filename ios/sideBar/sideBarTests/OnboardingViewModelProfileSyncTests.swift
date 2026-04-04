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

    func testValidateAndSaveApiKeyPublishesUpdatedSettingsResponse() async {
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
        viewModel.currentStep = .addApiKey
        viewModel.selectProvider(.anthropic)
        viewModel.apiKey = "sk-ant-1234567890"

        await viewModel.validateAndSaveApiKey()

        await fulfillment(of: [publishedSettings], timeout: 1.0)
        XCTAssertEqual(capturedSettings?.aiPrimaryProvider, "anthropic")
        XCTAssertEqual(capturedSettings?.aiPrimaryProviderHasKey, true)
        XCTAssertEqual(capturedSettings?.aiPrimaryProviderKeyLast4, "7890")
    }

    func testValidateAndSaveApiKeyPublishesUpdatedOnboardingState() async {
        let settingsAPI = OnboardingMockSettingsAPI()
        let onboardingAPI = MockOnboardingAPI()
        onboardingAPI.updateResult = .success(
            OnboardingState(
                status: .inProgress,
                providerReady: true,
                currentOnboardingStep: .permissionRecovery,
                isOnboardingComplete: false,
                intent: .chat,
                milestones: OnboardingMilestones(
                    providerConnected: "2026-04-04T16:00:00Z",
                    firstOutcomeCompleted: nil,
                    profileBasicsSet: nil,
                    communicationStyleSet: nil,
                    secondaryTourSeen: nil
                ),
                permissions: OnboardingPermissions(
                    location: .notAsked,
                    notifications: .notAsked
                ),
                lastPromptedAt: nil
            )
        )
        let publishedOnboarding = expectation(description: "Published onboarding state")
        var capturedOnboardingState: OnboardingState?

        let viewModel = OnboardingViewModel(
            authSession: MockAuthSessionForOnboarding(),
            onboardingAPI: onboardingAPI,
            settingsAPI: settingsAPI,
            onOnboardingUpdated: { state in
                capturedOnboardingState = state
                publishedOnboarding.fulfill()
            },
            userDefaults: makeUserDefaults()
        )
        viewModel.currentStep = .addApiKey
        viewModel.selectProvider(.anthropic)
        viewModel.apiKey = "sk-ant-1234567890"

        await viewModel.validateAndSaveApiKey()

        await fulfillment(of: [publishedOnboarding], timeout: 1.0)
        XCTAssertEqual(capturedOnboardingState?.providerReady, true)
        XCTAssertEqual(capturedOnboardingState?.currentOnboardingStep, .permissionRecovery)
    }
}
