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

    func testGoBackNotAllowedFromVerifyEmail() {
        let viewModel = makeViewModel()
        viewModel.currentStep = .verifyEmail

        viewModel.goBack()

        XCTAssertEqual(viewModel.currentStep, .verifyEmail)
    }

    func testStepHasBack() {
        let viewModel = makeViewModel()
        XCTAssertFalse(viewModel.currentStepHasBack)

        viewModel.currentStep = .createAccount
        XCTAssertTrue(viewModel.currentStepHasBack)

        viewModel.currentStep = .verifyEmail
        XCTAssertFalse(viewModel.currentStepHasBack)

        viewModel.currentStep = .profile
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

        XCTAssertEqual(viewModel.currentStep, .transition)
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

        XCTAssertEqual(viewModel.currentStep, .transition)
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

    private func makeViewModel() -> OnboardingViewModel {
        retain(OnboardingViewModel(
            authSession: MockAuthSessionForOnboarding(),
            onboardingAPI: MockOnboardingAPI(),
            settingsAPI: OnboardingMockSettingsAPI(),
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

final class MockOnboardingAPI: OnboardingProviding {
    var getResult: Result<OnboardingState, Error> = .success(.default)
    var updateResult: Result<OnboardingState, Error> = .success(.default)

    func getOnboarding() async throws -> OnboardingState {
        try getResult.get()
    }

    func updateOnboarding(_ update: OnboardingUpdate) async throws -> OnboardingState {
        _ = update
        return try updateResult.get()
    }
}

final class OnboardingMockSettingsAPI: SettingsProviding {
    var settings = UserSettings(
        userId: "u1",
        communicationStyle: nil,
        workingRelationship: nil,
        name: nil,
        jobTitle: nil,
        employer: nil,
        dateOfBirth: nil,
        gender: nil,
        pronouns: nil,
        location: nil,
        profileImageUrl: nil,
        enabledSkills: []
    )
    var providerKeyStatus = ProviderKeyStatusResponse(
        provider: "anthropic",
        hasKey: false,
        keyLast4: nil
    )
    var shortcutsToken = ShortcutsTokenResponse(token: "shortcuts-token")

    func getSettings() async throws -> UserSettings {
        settings
    }

    func updateSettings(_ update: SettingsUpdate) async throws -> UserSettings {
        _ = update
        return settings
    }

    func getProviderKeyStatus(provider: String?) async throws -> ProviderKeyStatusResponse {
        _ = provider
        return providerKeyStatus
    }

    func upsertProviderKey(provider: String, apiKey: String) async throws -> ProviderKeyStatusResponse {
        _ = provider
        _ = apiKey
        return providerKeyStatus
    }

    func deleteProviderKey(provider: String?) async throws -> ProviderKeyStatusResponse {
        _ = provider
        return providerKeyStatus
    }

    func disconnectProviderConsumer(
        provider: String,
        source: ProviderKeyDisconnectSource,
        skillId: String?
    ) async throws -> ProviderKeyDisconnectResponse {
        ProviderKeyDisconnectResponse(
            provider: provider,
            source: source,
            actions: ProviderKeyDisconnectActions(
                disabledSkillIds: skillId.map { [$0] } ?? [],
                detachedAIProvider: false,
                deletedProviderKey: false
            ),
            remainingConsumers: ProviderKeyDisconnectRemainingConsumers(
                aiProvider: false,
                skillIds: []
            ),
            settings: ProviderKeyDisconnectSettings(
                enabledSkills: [],
                installedStoreSkills: [],
                aiPrimaryProvider: nil
            )
        )
    }

    func getShortcutsToken() async throws -> ShortcutsTokenResponse {
        shortcutsToken
    }

    func rotateShortcutsToken() async throws -> ShortcutsTokenResponse {
        shortcutsToken
    }

    func uploadProfileImage(data: Data, contentType: String, filename: String) async throws {
        _ = data
        _ = contentType
        _ = filename
    }

    func getProfileImage() async throws -> Data {
        Data()
    }

    func deleteProfileImage() async throws {
    }
}

extension OnboardingState {
    static let `default` = OnboardingState(
        status: .notStarted,
        providerReady: false,
        intent: nil,
        milestones: OnboardingMilestones(
            providerConnected: nil,
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
}

@MainActor
final class MockAuthSessionForOnboarding: AuthSession {
    var accessToken: String?
    var userId: String?
    var authState: AuthState = .signedOut
    var pendingVerificationEmail: String?
    var signUpError: Error?
    var verifyOTPError: Error?

    var authorizationToken: String? {
        authState == .active ? accessToken : nil
    }

    func signIn(email: String, password: String) async throws {
        _ = email
        _ = password
    }

    func signUp(email: String, password: String) async throws {
        _ = password
        if let signUpError {
            throw signUpError
        }
        pendingVerificationEmail = email
    }

    func verifyOTP(email: String, code: String) async throws {
        _ = email
        _ = code
        if let verifyOTPError {
            throw verifyOTPError
        }
        authState = .active
        userId = "test-user-id"
        accessToken = "test-token"
        pendingVerificationEmail = nil
    }

    func refreshSession() async {
    }

    func refreshSessionIfStale() async {
    }

    func signOut() async {
        accessToken = nil
        userId = nil
        authState = .signedOut
        pendingVerificationEmail = nil
    }
}
