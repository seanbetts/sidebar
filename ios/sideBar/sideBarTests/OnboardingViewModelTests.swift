import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    private static var retainedViewModels: [OnboardingViewModel] = []

    func testInitialStepIsWelcome() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.currentStep, .welcome)
    }

    func testAdvanceFromWelcomeGoesToCreateAccount() {
        let viewModel = makeViewModel()

        viewModel.advance()

        XCTAssertEqual(viewModel.currentStep, .createAccount)
    }

    func testGoBackFromCreateAccountReturnsToWelcome() {
        let viewModel = makeViewModel()
        viewModel.advance()

        viewModel.goBack()

        XCTAssertEqual(viewModel.currentStep, .welcome)
    }

    func testGoBackNotAllowedFromWelcome() {
        let viewModel = makeViewModel()

        viewModel.goBack()

        XCTAssertEqual(viewModel.currentStep, .welcome)
    }

    func testGoBackFromVerifyEmailReturnsToCreateAccount() {
        let viewModel = makeViewModel()
        viewModel.currentStep = .verifyEmail

        viewModel.goBack()

        XCTAssertEqual(viewModel.currentStep, .createAccount)
    }

    func testTotalStepsIsNine() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.totalSteps, 9)
    }

    func testAdvanceFromAddApiKeyGoesToLocationPermission() {
        let viewModel = makeViewModel()
        viewModel.currentStep = .addApiKey

        viewModel.advance()

        XCTAssertEqual(viewModel.currentStep, .locationPermission)
    }

    func testAdvanceFromLocationPermissionRequiresResolution() {
        let viewModel = makeViewModel()
        viewModel.currentStep = .locationPermission

        viewModel.advance()

        XCTAssertEqual(viewModel.currentStep, .locationPermission)
    }

    func testAdvanceFromNotificationsPermissionRequiresResolution() {
        let viewModel = makeViewModel()
        viewModel.currentStep = .notificationsPermission

        viewModel.advance()

        XCTAssertEqual(viewModel.currentStep, .notificationsPermission)
    }

    func testAdvanceSetsNavigationDirectionForward() {
        let viewModel = makeViewModel()
        viewModel.currentStep = .addApiKey

        viewModel.advance()

        XCTAssertEqual(viewModel.navigationDirection, .forward)
    }

    func testGoBackFromNotificationsPermissionReturnsToLocationPermission() {
        let viewModel = makeViewModel()
        viewModel.currentStep = .notificationsPermission

        viewModel.goBack()

        XCTAssertEqual(viewModel.currentStep, .locationPermission)
    }

    func testGoBackSetsNavigationDirectionBackward() {
        let viewModel = makeViewModel()
        viewModel.currentStep = .notificationsPermission

        viewModel.goBack()

        XCTAssertEqual(viewModel.navigationDirection, .backward)
    }

    func testStepHasBack() {
        let viewModel = makeViewModel()
        XCTAssertFalse(viewModel.currentStepHasBack)

        viewModel.currentStep = .createAccount
        XCTAssertTrue(viewModel.currentStepHasBack)

        viewModel.currentStep = .verifyEmail
        XCTAssertTrue(viewModel.currentStepHasBack)

        viewModel.currentStep = .profile
        XCTAssertTrue(viewModel.currentStepHasBack)

        viewModel.currentStep = .locationPermission
        XCTAssertTrue(viewModel.currentStepHasBack)

        viewModel.currentStep = .notificationsPermission
        XCTAssertTrue(viewModel.currentStepHasBack)

        viewModel.currentStep = .finalStep
        XCTAssertTrue(viewModel.currentStepHasBack)
    }

    func testEmailValidation() {
        let viewModel = makeViewModel()
        viewModel.email = "notanemail"
        XCTAssertFalse(viewModel.isEmailValid)

        viewModel.email = "test@example.com"
        XCTAssertTrue(viewModel.isEmailValid)

        viewModel.email = ""
        XCTAssertFalse(viewModel.isEmailValid)
    }

    func testPasswordStrength() {
        let viewModel = makeViewModel()
        viewModel.password = ""
        XCTAssertEqual(viewModel.passwordStrength, 0)

        viewModel.password = "1234567"
        XCTAssertEqual(viewModel.passwordStrength, 0)

        viewModel.password = "abcdefgh"
        XCTAssertEqual(viewModel.passwordStrength, 1)

        viewModel.password = "Abcdefgh"
        XCTAssertEqual(viewModel.passwordStrength, 2)

        viewModel.password = "Abcdefg1"
        XCTAssertEqual(viewModel.passwordStrength, 3)

        viewModel.password = "Abcdefg1!"
        XCTAssertEqual(viewModel.passwordStrength, 4)
    }

    func testCreateAccountFormNotValidUntilEmailAndPasswordMeetMinimum() {
        let viewModel = makeViewModel()
        viewModel.email = "test@example.com"
        viewModel.password = "short"
        XCTAssertFalse(viewModel.isCreateAccountValid)

        viewModel.password = "LongEnough1"
        XCTAssertTrue(viewModel.isCreateAccountValid)
    }

    func testSelectProvider() {
        let viewModel = makeViewModel()
        XCTAssertNil(viewModel.selectedProvider)

        viewModel.selectedProvider = .anthropic

        XCTAssertEqual(viewModel.selectedProvider, .anthropic)
    }

    func testAdvanceFromChooseProviderRequiresSelection() {
        let viewModel = makeViewModel()
        viewModel.currentStep = .chooseProvider

        viewModel.advance()

        XCTAssertEqual(viewModel.currentStep, .chooseProvider)
    }

    func testSelectingProviderClearsMissingProviderErrorBeforeReturningToApiKey() async {
        let viewModel = makeViewModel()
        viewModel.currentStep = .addApiKey

        await viewModel.validateAndSaveApiKey()
        XCTAssertEqual(viewModel.errorMessage, "Please go back and select a provider.")

        viewModel.currentStep = .chooseProvider
        viewModel.selectProvider(.anthropic)
        viewModel.advance(from: .chooseProvider)

        XCTAssertEqual(viewModel.currentStep, .addApiKey)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.selectedProvider, .anthropic)
    }

    func testApiKeyTrimmed() {
        let viewModel = makeViewModel()
        viewModel.apiKey = "  sk-ant-abc123  "

        XCTAssertEqual(viewModel.trimmedApiKey, "sk-ant-abc123")
    }

    func testResetOnboardingFlagDetected() {
        let viewModel = retain(OnboardingViewModel(
            authSession: MockAuthSessionForOnboarding(),
            onboardingAPI: MockOnboardingAPI(),
            settingsAPI: OnboardingMockSettingsAPI(),
            isTestingOnboarding: true,
            userDefaults: makeUserDefaults()
        ))

        XCTAssertTrue(viewModel.isTestingOnboarding)
    }

    func testCreateAccountAdvancesToVerifyEmail() async {
        let mockAuth = MockAuthSessionForOnboarding()
        let viewModel = retain(OnboardingViewModel(
            authSession: mockAuth,
            onboardingAPI: MockOnboardingAPI(),
            settingsAPI: OnboardingMockSettingsAPI(),
            userDefaults: makeUserDefaults()
        ))
        viewModel.email = "test@example.com"
        viewModel.password = "StrongPass1!"
        viewModel.currentStep = .createAccount

        await viewModel.createAccount()

        XCTAssertEqual(viewModel.currentStep, .verifyEmail)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testCreateAccountShowsErrorOnFailure() async {
        let mockAuth = MockAuthSessionForOnboarding()
        mockAuth.signUpError = AuthAdapterError.unknown("Email taken")
        let viewModel = retain(OnboardingViewModel(
            authSession: mockAuth,
            onboardingAPI: MockOnboardingAPI(),
            settingsAPI: OnboardingMockSettingsAPI(),
            userDefaults: makeUserDefaults()
        ))
        viewModel.email = "test@example.com"
        viewModel.password = "StrongPass1!"
        viewModel.currentStep = .createAccount

        await viewModel.createAccount()

        XCTAssertEqual(viewModel.currentStep, .createAccount)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testVerifyOTPAdvancesToProfile() async {
        let mockAuth = MockAuthSessionForOnboarding()
        let viewModel = retain(OnboardingViewModel(
            authSession: mockAuth,
            onboardingAPI: MockOnboardingAPI(),
            settingsAPI: OnboardingMockSettingsAPI(),
            userDefaults: makeUserDefaults()
        ))
        viewModel.currentStep = .verifyEmail

        await viewModel.verifyOTP(code: "123456")

        XCTAssertEqual(viewModel.currentStep, .profile)
    }

    func testValidateApiKeyAdvancesToTransition() async {
        let viewModel = retain(OnboardingViewModel(
            authSession: MockAuthSessionForOnboarding(),
            onboardingAPI: MockOnboardingAPI(),
            settingsAPI: OnboardingMockSettingsAPI(),
            isTestingOnboarding: true,
            userDefaults: makeUserDefaults()
        ))
        viewModel.selectedProvider = .anthropic
        viewModel.apiKey = "sk-ant-valid-key"
        viewModel.currentStep = .addApiKey

        await viewModel.validateAndSaveApiKey()

        XCTAssertEqual(viewModel.currentStep, .locationPermission)
        XCTAssertEqual(viewModel.transitionVariant, .providerConnected)
    }

    func testValidateApiKeyShowsErrorOnEmpty() async {
        let viewModel = retain(OnboardingViewModel(
            authSession: MockAuthSessionForOnboarding(),
            onboardingAPI: MockOnboardingAPI(),
            settingsAPI: OnboardingMockSettingsAPI(),
            userDefaults: makeUserDefaults()
        ))
        viewModel.selectedProvider = .anthropic
        viewModel.apiKey = ""
        viewModel.currentStep = .addApiKey

        await viewModel.validateAndSaveApiKey()

        XCTAssertEqual(viewModel.currentStep, .addApiKey)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testSkipLocationPermissionWritesNotAskedAndAdvancesToNotificationsPermission() async {
        let onboardingAPI = MockOnboardingAPI()
        let viewModel = makeViewModel(
            onboardingAPI: onboardingAPI,
            locationPermissionRequester: MockLocationPermissionRequester(),
            notificationsPermissionRequester: MockNotificationPermissionRequester()
        )
        viewModel.currentStep = .locationPermission

        await viewModel.skipLocationPermission()

        XCTAssertEqual(viewModel.locationPermissionState, .notAsked)
        XCTAssertTrue(viewModel.isLocationPermissionResolved)
        XCTAssertEqual(viewModel.currentStep, .notificationsPermission)
        XCTAssertEqual(onboardingAPI.updates.last?.locationPermission, .notAsked)
    }

    func testSkipProviderSetupDoesNotResolvePermissionSteps() async {
        let viewModel = makeViewModel()
        viewModel.currentStep = .chooseProvider

        await viewModel.skipProviderSetup()

        XCTAssertFalse(viewModel.isLocationPermissionResolved)
        XCTAssertFalse(viewModel.isNotificationsPermissionResolved)
        XCTAssertEqual(viewModel.locationPermissionState, .notAsked)
        XCTAssertEqual(viewModel.notificationsPermissionState, .notAsked)
    }

    func testSaveProfileOnlyAdvancesOnceWhenTriggeredTwice() async {
        let viewModel = makeViewModel()
        viewModel.currentStep = .profile

        await viewModel.saveProfile()
        await viewModel.saveProfile()

        XCTAssertEqual(viewModel.currentStep, .chooseProvider)
    }

    func testSaveProfileAdvancesImmediatelyWhileBackgroundSaveIsInFlight() async {
        let onboardingAPI = MockOnboardingAPI()
        let settingsAPI = DelayedProfileSettingsAPI()
        settingsAPI.updateDelayNanoseconds = 2_000_000_000
        let updateStarted = expectation(description: "Profile settings update started")
        let updateCompleted = expectation(description: "Profile settings update completed")
        settingsAPI.onUpdateStarted = {
            updateStarted.fulfill()
        }
        settingsAPI.onUpdateCompleted = {
            updateCompleted.fulfill()
        }

        let viewModel = retain(OnboardingViewModel(
            authSession: MockAuthSessionForOnboarding(),
            onboardingAPI: onboardingAPI,
            settingsAPI: settingsAPI,
            userDefaults: makeUserDefaults()
        ))
        viewModel.currentStep = .profile
        viewModel.displayName = "Sean"

        let saveTask = Task { await viewModel.saveProfile() }

        await fulfillment(of: [updateStarted], timeout: 1.0)
        XCTAssertEqual(viewModel.currentStep, .chooseProvider)
        await saveTask.value
        await fulfillment(of: [updateCompleted], timeout: 3.0)
    }

    func testCompleteOnboardingReturnsImmediatelyWhileBackendUpdateIsInFlight() async {
        let onboardingAPI = DelayedOnboardingAPI()
        onboardingAPI.updateDelayNanoseconds = 2_000_000_000
        let updateStarted = expectation(description: "Onboarding completion update started")
        let updateCompleted = expectation(description: "Onboarding completion update completed")
        let completionReturned = expectation(description: "Completion call returned")
        onboardingAPI.onUpdateStarted = {
            updateStarted.fulfill()
        }
        onboardingAPI.onUpdateCompleted = {
            updateCompleted.fulfill()
        }
        let userDefaults = makeUserDefaults()
        let viewModel = retain(OnboardingViewModel(
            authSession: MockAuthSessionForOnboarding(),
            onboardingAPI: onboardingAPI,
            settingsAPI: OnboardingMockSettingsAPI(),
            userDefaults: userDefaults
        ))
        viewModel.currentStep = .finalStep

        Task {
            await viewModel.completeOnboarding()
            completionReturned.fulfill()
        }

        await fulfillment(of: [updateStarted], timeout: 1.0)
        await fulfillment(of: [completionReturned], timeout: 0.2)
        XCTAssertEqual(
            userDefaults.string(forKey: AppStorageKeys.onboardingStatus),
            OnboardingStatus.completed.rawValue
        )
        await fulfillment(of: [updateCompleted], timeout: 3.0)
    }

    func testTestingModeSkipsRealAuth() async {
        let viewModel = retain(OnboardingViewModel(
            authSession: MockAuthSessionForOnboarding(),
            onboardingAPI: MockOnboardingAPI(),
            settingsAPI: OnboardingMockSettingsAPI(),
            isTestingOnboarding: true,
            userDefaults: makeUserDefaults()
        ))
        viewModel.currentStep = .createAccount

        await viewModel.createAccount()

        XCTAssertEqual(viewModel.currentStep, .verifyEmail)
    }

    func testTestingModeAcceptsAnyApiKey() async {
        let viewModel = retain(OnboardingViewModel(
            authSession: MockAuthSessionForOnboarding(),
            onboardingAPI: MockOnboardingAPI(),
            settingsAPI: OnboardingMockSettingsAPI(),
            isTestingOnboarding: true,
            userDefaults: makeUserDefaults()
        ))
        viewModel.selectedProvider = .anthropic
        viewModel.apiKey = "literally-anything"
        viewModel.currentStep = .addApiKey

        await viewModel.validateAndSaveApiKey()

        XCTAssertEqual(viewModel.currentStep, .locationPermission)
        XCTAssertEqual(viewModel.transitionVariant, .providerConnected)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testTestingModeSkipsRealVerification() async {
        let viewModel = retain(OnboardingViewModel(
            authSession: MockAuthSessionForOnboarding(),
            onboardingAPI: MockOnboardingAPI(),
            settingsAPI: OnboardingMockSettingsAPI(),
            isTestingOnboarding: true,
            userDefaults: makeUserDefaults()
        ))
        viewModel.currentStep = .verifyEmail

        await viewModel.verifyOTP(code: "000000")

        XCTAssertEqual(viewModel.currentStep, .profile)
    }

    private func makeViewModel(
        onboardingAPI: MockOnboardingAPI = MockOnboardingAPI(),
        locationPermissionRequester: (any LocationPermissionRequesting)? = nil,
        notificationsPermissionRequester: (any NotificationPermissionRequesting)? = nil
    ) -> OnboardingViewModel {
        retain(OnboardingViewModel(
            authSession: MockAuthSessionForOnboarding(),
            onboardingAPI: onboardingAPI,
            settingsAPI: OnboardingMockSettingsAPI(),
            locationPermissionRequester: locationPermissionRequester ?? MockLocationPermissionRequester(),
            notificationsPermissionRequester: notificationsPermissionRequester ?? MockNotificationPermissionRequester(),
            userDefaults: makeUserDefaults()
        ))
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "OnboardingViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func retain(_ viewModel: OnboardingViewModel) -> OnboardingViewModel {
        Self.retainedViewModels.append(viewModel)
        return viewModel
    }
}
