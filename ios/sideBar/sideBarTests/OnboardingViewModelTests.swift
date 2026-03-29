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

    func testEnableLocationPermissionGrantedWritesGrantedAndAdvancesToNotificationsPermission() async {
        let onboardingAPI = MockOnboardingAPI()
        let locationRequester = MockLocationPermissionRequester()
        locationRequester.requestResult = .granted
        let viewModel = makeViewModel(
            onboardingAPI: onboardingAPI,
            locationPermissionRequester: locationRequester,
            notificationsPermissionRequester: MockNotificationPermissionRequester()
        )
        viewModel.currentStep = .locationPermission

        await viewModel.enableLocationPermission()

        XCTAssertEqual(locationRequester.requestCount, 1)
        XCTAssertEqual(viewModel.locationPermissionState, .granted)
        XCTAssertTrue(viewModel.isLocationPermissionResolved)
        XCTAssertEqual(viewModel.currentStep, .notificationsPermission)
        XCTAssertEqual(onboardingAPI.updates.last?.locationPermission, .granted)
    }

    func testEnableLocationPermissionDeniedWritesDeniedAndStillAdvances() async {
        let onboardingAPI = MockOnboardingAPI()
        let locationRequester = MockLocationPermissionRequester()
        locationRequester.requestResult = .denied
        let viewModel = makeViewModel(
            onboardingAPI: onboardingAPI,
            locationPermissionRequester: locationRequester,
            notificationsPermissionRequester: MockNotificationPermissionRequester()
        )
        viewModel.currentStep = .locationPermission

        await viewModel.enableLocationPermission()

        XCTAssertEqual(viewModel.locationPermissionState, .denied)
        XCTAssertTrue(viewModel.isLocationPermissionResolved)
        XCTAssertEqual(viewModel.currentStep, .notificationsPermission)
        XCTAssertEqual(onboardingAPI.updates.last?.locationPermission, .denied)
    }

    func testSkipNotificationsPermissionWritesNotAskedAndAdvancesToFinalStep() async {
        let onboardingAPI = MockOnboardingAPI()
        let viewModel = makeViewModel(
            onboardingAPI: onboardingAPI,
            locationPermissionRequester: MockLocationPermissionRequester(),
            notificationsPermissionRequester: MockNotificationPermissionRequester()
        )
        viewModel.currentStep = .notificationsPermission

        await viewModel.skipNotificationsPermission()

        XCTAssertEqual(viewModel.notificationsPermissionState, .notAsked)
        XCTAssertTrue(viewModel.isNotificationsPermissionResolved)
        XCTAssertEqual(viewModel.currentStep, .finalStep)
        XCTAssertEqual(onboardingAPI.updates.last?.notificationsPermission, .notAsked)
    }

    func testEnableNotificationsPermissionGrantedWritesGrantedAndAdvancesToFinalStep() async {
        let onboardingAPI = MockOnboardingAPI()
        let notificationsRequester = MockNotificationPermissionRequester()
        notificationsRequester.requestResult = .granted
        let viewModel = makeViewModel(
            onboardingAPI: onboardingAPI,
            locationPermissionRequester: MockLocationPermissionRequester(),
            notificationsPermissionRequester: notificationsRequester
        )
        viewModel.currentStep = .notificationsPermission

        await viewModel.enableNotificationsPermission()

        XCTAssertEqual(notificationsRequester.requestCount, 1)
        XCTAssertEqual(viewModel.notificationsPermissionState, .granted)
        XCTAssertTrue(viewModel.isNotificationsPermissionResolved)
        XCTAssertEqual(viewModel.currentStep, .finalStep)
        XCTAssertEqual(onboardingAPI.updates.last?.notificationsPermission, .granted)
    }

    func testSaveProfileOnlyAdvancesOnceWhenTriggeredTwice() async {
        let viewModel = makeViewModel()
        viewModel.currentStep = .profile

        await viewModel.saveProfile()
        await viewModel.saveProfile()

        XCTAssertEqual(viewModel.currentStep, .chooseProvider)
    }

    func testResolvedLocationPermissionDoesNotRequestAgainWhenRevisited() async {
        let onboardingAPI = MockOnboardingAPI()
        let locationRequester = MockLocationPermissionRequester()
        locationRequester.requestResult = .granted
        let viewModel = makeViewModel(
            onboardingAPI: onboardingAPI,
            locationPermissionRequester: locationRequester,
            notificationsPermissionRequester: MockNotificationPermissionRequester()
        )
        viewModel.currentStep = .locationPermission

        await viewModel.enableLocationPermission()
        viewModel.goBack()
        await viewModel.enableLocationPermission()

        XCTAssertEqual(locationRequester.requestCount, 1)
        XCTAssertEqual(viewModel.currentStep, .notificationsPermission)
        XCTAssertEqual(
            onboardingAPI.updates.compactMap(\.locationPermission),
            [.granted]
        )
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
