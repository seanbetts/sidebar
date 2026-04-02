import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class OnboardingKeyValidationTests: XCTestCase {
    func testValidateApiKeyShowsInvalidKeyErrorWithoutPersistingProvider() async {
        let settingsAPI = OnboardingMockSettingsAPI()
        settingsAPI.upsertProviderKeyResult = .failure(
            APIClientError.apiError("Invalid provider API key")
        )
        let viewModel = OnboardingViewModel(
            authSession: MockAuthSessionForOnboarding(),
            onboardingAPI: MockOnboardingAPI(),
            settingsAPI: settingsAPI,
            userDefaults: makeUserDefaults()
        )
        viewModel.selectedProvider = .anthropic
        viewModel.apiKey = "invalid-key"
        viewModel.currentStep = .addApiKey

        await viewModel.validateAndSaveApiKey()

        XCTAssertEqual(viewModel.currentStep, .addApiKey)
        XCTAssertEqual(
            viewModel.errorMessage,
            "That API key doesn't look valid for this provider."
        )
        XCTAssertTrue(settingsAPI.updates.isEmpty)
    }

    func testTestingModeStillValidatesApiKey() async {
        let settingsAPI = OnboardingMockSettingsAPI()
        settingsAPI.upsertProviderKeyResult = .failure(
            APIClientError.apiError("Invalid provider API key")
        )
        let viewModel = OnboardingViewModel(
            authSession: MockAuthSessionForOnboarding(),
            onboardingAPI: MockOnboardingAPI(),
            settingsAPI: settingsAPI,
            isTestingOnboarding: true,
            userDefaults: makeUserDefaults()
        )
        viewModel.selectedProvider = .anthropic
        viewModel.apiKey = "sk-ant-definitely-not-real"
        viewModel.currentStep = .addApiKey

        await viewModel.validateAndSaveApiKey()

        XCTAssertEqual(viewModel.currentStep, .addApiKey)
        XCTAssertEqual(
            viewModel.errorMessage,
            "That API key doesn't look valid for this provider."
        )
    }

    func testTestingModeUsesProviderKeyFallbackMessageForBareBadRequest() async {
        let settingsAPI = OnboardingMockSettingsAPI()
        settingsAPI.upsertProviderKeyResult = .failure(APIClientError.requestFailed(400))
        let viewModel = OnboardingViewModel(
            authSession: MockAuthSessionForOnboarding(),
            onboardingAPI: MockOnboardingAPI(),
            settingsAPI: settingsAPI,
            isTestingOnboarding: true,
            userDefaults: makeUserDefaults()
        )
        viewModel.selectedProvider = .anthropic
        viewModel.apiKey = "sk-ant-definitely-not-real"
        viewModel.currentStep = .addApiKey

        await viewModel.validateAndSaveApiKey()

        XCTAssertEqual(viewModel.currentStep, .addApiKey)
        XCTAssertEqual(
            viewModel.errorMessage,
            "We couldn't verify that API key. Check it and try again."
        )
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "OnboardingKeyValidationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
