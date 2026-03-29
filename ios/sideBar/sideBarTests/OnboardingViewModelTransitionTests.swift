import XCTest
@testable import sideBar

@MainActor
final class OnboardingViewModelTransitionTests: XCTestCase {
    func testGoBackFromFinalStepReturnsToNotificationsPermission() {
        let viewModel = makeViewModel(isTestingOnboarding: true)
        viewModel.currentStep = .finalStep

        viewModel.goBack()

        XCTAssertEqual(viewModel.currentStep, .notificationsPermission)
    }

    func testConnectedProviderTransitionKeepsExistingAllSetContent() async {
        let viewModel = makeViewModel(isTestingOnboarding: true)
        viewModel.selectedProvider = .anthropic
        viewModel.apiKey = "sk-ant-valid-key"
        viewModel.currentStep = .addApiKey

        await viewModel.validateAndSaveApiKey()

        viewModel.currentStep = .finalStep
        XCTAssertEqual(viewModel.transitionTitle, "You're All Set")
        XCTAssertEqual(viewModel.transitionSubtitle, "I'm connected and ready to go.\nLet me show you around.")
        XCTAssertTrue(viewModel.transitionHighlights.isEmpty)
    }

    func testSkipProviderSetupUsesSkippedTransitionVariantInTestingMode() async {
        let viewModel = makeViewModel(isTestingOnboarding: true)
        viewModel.currentStep = .addApiKey

        await viewModel.skipProviderSetup()

        XCTAssertEqual(viewModel.currentStep, .locationPermission)
        XCTAssertEqual(viewModel.transitionVariant, .providerSetupSkipped)
    }

    func testSkipProviderSetupUsesSkippedTransitionVariant() async {
        let viewModel = makeViewModel()
        viewModel.currentStep = .addApiKey

        await viewModel.skipProviderSetup()

        XCTAssertEqual(viewModel.currentStep, .locationPermission)
        XCTAssertEqual(viewModel.transitionVariant, .providerSetupSkipped)
    }

    func testSkippedProviderTransitionContentExplainsCapabilitiesAndLimitations() async {
        let viewModel = makeViewModel()

        await viewModel.skipProviderSetup()

        XCTAssertEqual(viewModel.transitionTitle, "You're Ready To Explore")
        XCTAssertEqual(
            viewModel.transitionSubtitle,
            "You can start using sideBar now, even without connecting an AI provider yet."
        )
        XCTAssertEqual(
            viewModel.transitionHighlights,
            [
                "You can still capture notes, tasks, files, and save websites to read later.",
                "Chat and other assistant-powered features stay unavailable until you add an API key.",
                "You can connect your AI brain later in Settings whenever you're ready."
            ]
        )
    }

    func testFinalStepShowsBackWhenProviderSetupWasSkipped() {
        let viewModel = makeViewModel(isTestingOnboarding: true)
        viewModel.currentStep = .finalStep

        XCTAssertTrue(viewModel.currentStepHasBack)
    }

    func testGoBackFromFinalStepReturnsToNotificationsPermissionWhenProviderSetupWasSkipped() async {
        let viewModel = makeViewModel(isTestingOnboarding: true)
        viewModel.currentStep = .chooseProvider

        await viewModel.skipProviderSetup()
        viewModel.currentStep = .finalStep
        viewModel.goBack()

        XCTAssertEqual(viewModel.currentStep, .notificationsPermission)
    }

    func testGoBackFromLocationPermissionReturnsToChooseProviderWhenProviderSetupWasSkipped() async {
        let viewModel = makeViewModel(isTestingOnboarding: true)
        viewModel.currentStep = .chooseProvider

        await viewModel.skipProviderSetup()
        viewModel.goBack()

        XCTAssertEqual(viewModel.currentStep, .chooseProvider)
    }

    func testGoBackFromFinalStepReturnsToNotificationsPermissionWhenProviderIsConnected() async {
        let viewModel = makeViewModel(isTestingOnboarding: true)
        viewModel.selectedProvider = .anthropic
        viewModel.currentStep = .addApiKey

        await viewModel.validateAndSaveApiKey()
        viewModel.currentStep = .finalStep
        viewModel.goBack()

        XCTAssertEqual(viewModel.currentStep, .notificationsPermission)
    }

    private func makeViewModel(isTestingOnboarding: Bool = false) -> OnboardingViewModel {
        OnboardingViewModel(
            authSession: MockAuthSessionForOnboarding(),
            onboardingAPI: MockOnboardingAPI(),
            settingsAPI: OnboardingMockSettingsAPI(),
            isTestingOnboarding: isTestingOnboarding,
            userDefaults: makeUserDefaults()
        )
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "OnboardingViewModelTransitionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
