import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class OnboardingViewModelPermissionTests: XCTestCase {
    private static var retainedViewModels: [OnboardingViewModel] = []

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

    func testSkippedLocationPermissionCanBeRequestedWhenRevisited() async {
        let onboardingAPI = MockOnboardingAPI()
        let locationRequester = MockLocationPermissionRequester()
        locationRequester.requestResult = .granted
        let viewModel = makeViewModel(
            onboardingAPI: onboardingAPI,
            locationPermissionRequester: locationRequester,
            notificationsPermissionRequester: MockNotificationPermissionRequester()
        )
        viewModel.currentStep = .locationPermission

        await viewModel.skipLocationPermission()
        viewModel.goBack()
        await viewModel.enableLocationPermission()

        XCTAssertEqual(locationRequester.requestCount, 1)
        XCTAssertEqual(viewModel.locationPermissionState, .granted)
        XCTAssertEqual(viewModel.currentStep, .notificationsPermission)
        XCTAssertEqual(
            onboardingAPI.updates.compactMap(\.locationPermission),
            [.notAsked, .granted]
        )
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

    func testSkippedNotificationsPermissionCanBeRequestedWhenRevisited() async {
        let onboardingAPI = MockOnboardingAPI()
        let notificationsRequester = MockNotificationPermissionRequester()
        notificationsRequester.requestResult = .granted
        let viewModel = makeViewModel(
            onboardingAPI: onboardingAPI,
            locationPermissionRequester: MockLocationPermissionRequester(),
            notificationsPermissionRequester: notificationsRequester
        )
        viewModel.currentStep = .notificationsPermission

        await viewModel.skipNotificationsPermission()
        viewModel.goBack()
        await viewModel.enableNotificationsPermission()

        XCTAssertEqual(notificationsRequester.requestCount, 1)
        XCTAssertEqual(viewModel.notificationsPermissionState, .granted)
        XCTAssertEqual(viewModel.currentStep, .finalStep)
        XCTAssertEqual(
            onboardingAPI.updates.compactMap(\.notificationsPermission),
            [.notAsked, .granted]
        )
    }

    func testRefreshCurrentPermissionStateUpgradesSkippedNotificationsToGrantedWhenRevisitingStep() async {
        let notificationsRequester = MockNotificationPermissionRequester()
        notificationsRequester.currentStateValue = .granted
        let viewModel = makeViewModel(
            locationPermissionRequester: MockLocationPermissionRequester(),
            notificationsPermissionRequester: notificationsRequester
        )
        viewModel.currentStep = .notificationsPermission
        await viewModel.skipNotificationsPermission()
        viewModel.goBack()
        viewModel.currentStep = .notificationsPermission

        await viewModel.refreshPermissionStateForCurrentStep()

        XCTAssertEqual(viewModel.notificationsPermissionState, .granted)
        XCTAssertTrue(viewModel.isNotificationsPermissionResolved)
        XCTAssertEqual(viewModel.currentStep, .notificationsPermission)
    }

    func testGoingBackToNotificationsPermissionRefreshesGrantedSystemState() async {
        let notificationsRequester = MockNotificationPermissionRequester()
        let viewModel = makeViewModel(
            locationPermissionRequester: MockLocationPermissionRequester(),
            notificationsPermissionRequester: notificationsRequester
        )
        viewModel.currentStep = .notificationsPermission

        await viewModel.skipNotificationsPermission()
        notificationsRequester.currentStateValue = .granted

        viewModel.goBack()

        XCTAssertEqual(viewModel.currentStep, .notificationsPermission)
        XCTAssertEqual(viewModel.notificationsPermissionState, .granted)
        XCTAssertTrue(viewModel.isNotificationsPermissionResolved)
    }

    func testGoingBackToNotificationsPermissionUsesCachedGrantedStateImmediately() async {
        let notificationsRequester = MockNotificationPermissionRequester()
        notificationsRequester.currentStateValue = .granted
        let viewModel = makeViewModel(
            locationPermissionRequester: MockLocationPermissionRequester(),
            notificationsPermissionRequester: notificationsRequester
        )
        viewModel.currentStep = .finalStep

        viewModel.goBack()

        XCTAssertEqual(viewModel.currentStep, .notificationsPermission)
        XCTAssertEqual(viewModel.notificationsPermissionState, .granted)
        XCTAssertTrue(viewModel.isNotificationsPermissionResolved)
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
        let suiteName = "OnboardingViewModelPermissionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func retain(_ viewModel: OnboardingViewModel) -> OnboardingViewModel {
        Self.retainedViewModels.append(viewModel)
        return viewModel
    }
}
