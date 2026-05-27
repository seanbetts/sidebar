import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class OnboardingViewModelMilestoneSyncTests: XCTestCase {
    func testVerifyOTPAdvancesWhenOnboardingStatusSyncFails() async {
        let onboardingAPI = MockOnboardingAPI()
        onboardingAPI.updateResult = .failure(APIClientError.requestFailed(503))
        let sync = OnboardingSyncCoordinator(
            api: onboardingAPI,
            localStateStore: OnboardingLocalStateStore(cache: TestCacheClient()),
            writeQueue: nil
        )
        let defaults = makeUserDefaults()
        let viewModel = OnboardingViewModel(
            authSession: MockAuthSessionForOnboarding(),
            onboardingAPI: onboardingAPI,
            settingsAPI: OnboardingMockSettingsAPI(),
            onboardingSync: sync,
            userDefaults: defaults
        )
        viewModel.currentStep = .verifyEmail

        await viewModel.verifyOTP(code: "123456")

        XCTAssertEqual(viewModel.currentStep, .profile)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(
            defaults.string(forKey: AppStorageKeys.onboardingStatus),
            OnboardingStatus.inProgress.rawValue
        )
        XCTAssertEqual(sync.cachedState()?.status, .inProgress)
    }

    func testSaveProfileAdvancesWhenMilestoneSyncFailsAfterSettingsSave() async {
        let onboardingAPI = MockOnboardingAPI()
        onboardingAPI.updateResult = .failure(APIClientError.requestFailed(503))
        let sync = OnboardingSyncCoordinator(
            api: onboardingAPI,
            localStateStore: OnboardingLocalStateStore(cache: TestCacheClient()),
            writeQueue: nil
        )
        let viewModel = OnboardingViewModel(
            authSession: MockAuthSessionForOnboarding(),
            onboardingAPI: onboardingAPI,
            settingsAPI: OnboardingMockSettingsAPI(),
            onboardingSync: sync,
            userDefaults: makeUserDefaults()
        )
        viewModel.currentStep = .profile
        viewModel.displayName = "Sean"

        await viewModel.saveProfile()

        XCTAssertEqual(viewModel.currentStep, .chooseProvider)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNotNil(sync.cachedState()?.milestones.profileBasicsSet)
    }

    func testProviderSetupAdvancesWhenProviderMilestoneSyncFails() async {
        let onboardingAPI = MockOnboardingAPI()
        onboardingAPI.updateResult = .failure(APIClientError.requestFailed(503))
        let sync = OnboardingSyncCoordinator(
            api: onboardingAPI,
            localStateStore: OnboardingLocalStateStore(cache: TestCacheClient()),
            writeQueue: nil
        )
        let viewModel = OnboardingViewModel(
            authSession: MockAuthSessionForOnboarding(),
            onboardingAPI: onboardingAPI,
            settingsAPI: OnboardingMockSettingsAPI(),
            onboardingSync: sync,
            userDefaults: makeUserDefaults()
        )
        viewModel.currentStep = .addApiKey
        viewModel.selectProvider(.anthropic)
        viewModel.apiKey = "sk-ant-1234567890"

        await viewModel.validateAndSaveApiKey()

        XCTAssertEqual(viewModel.currentStep, .locationPermission)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNotNil(sync.cachedState()?.milestones.providerConnected)
    }

    func testPermissionStepAdvancesWhenPermissionSyncFails() async {
        let onboardingAPI = MockOnboardingAPI()
        onboardingAPI.updateResult = .failure(APIClientError.requestFailed(503))
        let sync = OnboardingSyncCoordinator(
            api: onboardingAPI,
            localStateStore: OnboardingLocalStateStore(cache: TestCacheClient()),
            writeQueue: nil
        )
        let locationRequester = MockLocationPermissionRequester()
        locationRequester.requestResult = .granted
        let viewModel = OnboardingViewModel(
            authSession: MockAuthSessionForOnboarding(),
            onboardingAPI: onboardingAPI,
            settingsAPI: OnboardingMockSettingsAPI(),
            onboardingSync: sync,
            locationPermissionRequester: locationRequester,
            userDefaults: makeUserDefaults()
        )
        viewModel.currentStep = .locationPermission

        await viewModel.enableLocationPermission()

        XCTAssertEqual(viewModel.currentStep, .notificationsPermission)
        XCTAssertEqual(sync.cachedState()?.permissions.location, .granted)
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "OnboardingViewModelMilestoneSyncTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
