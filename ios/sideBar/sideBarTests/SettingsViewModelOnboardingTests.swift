import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class SettingsViewModelOnboardingTests: XCTestCase {
    func testLoadOnboardingStoresSignedInRecoveryStateFromBackend() async {
        let onboardingState = OnboardingState(
            status: .dismissed,
            providerReady: false,
            currentOnboardingStep: .providerRecovery,
            isOnboardingComplete: false,
            intent: .notes,
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
        let onboardingAPI = MockOnboardingAPI()
        onboardingAPI.getResult = .success(onboardingState)
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(result: .failure(SettingsViewModelMockError.forced)),
            skillsAPI: MockSkillsAPI(result: .success(SkillsResponse(skills: []))),
            onboardingAPI: onboardingAPI,
            cache: TestCacheClient()
        )

        await viewModel.loadOnboarding()

        XCTAssertEqual(viewModel.onboardingState, onboardingState)
        XCTAssertEqual(viewModel.signedInOnboardingRecoveryState, .providerRecovery)
    }

    func testLoadOnboardingClearsRecoveryStateWhenBackendIsComplete() async {
        let onboardingState = OnboardingState(
            status: .completed,
            providerReady: true,
            currentOnboardingStep: .completed,
            isOnboardingComplete: true,
            intent: .notes,
            milestones: OnboardingMilestones(
                providerConnected: "2026-03-31T12:00:00Z",
                firstOutcomeCompleted: "2026-03-31T12:30:00Z",
                profileBasicsSet: nil,
                communicationStyleSet: nil,
                secondaryTourSeen: "2026-03-31T12:31:00Z"
            ),
            permissions: OnboardingPermissions(
                location: .granted,
                notifications: .granted
            ),
            lastPromptedAt: nil
        )
        let onboardingAPI = MockOnboardingAPI()
        onboardingAPI.getResult = .success(onboardingState)
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(result: .failure(SettingsViewModelMockError.forced)),
            skillsAPI: MockSkillsAPI(result: .success(SkillsResponse(skills: []))),
            onboardingAPI: onboardingAPI,
            cache: TestCacheClient()
        )

        await viewModel.loadOnboarding()

        XCTAssertEqual(viewModel.onboardingState, onboardingState)
        XCTAssertEqual(viewModel.signedInOnboardingRecoveryState, .none)
    }

    func testLoadOnboardingClearsRecoveryStateWhenBackendCompletesFromFirstOutcomeAlone() async {
        let onboardingState = OnboardingState(
            status: .completed,
            providerReady: true,
            currentOnboardingStep: .completed,
            isOnboardingComplete: true,
            intent: .notes,
            milestones: OnboardingMilestones(
                providerConnected: "2026-04-02T11:00:00Z",
                firstOutcomeCompleted: "2026-04-02T11:05:00Z",
                profileBasicsSet: nil,
                communicationStyleSet: nil,
                secondaryTourSeen: nil
            ),
            permissions: OnboardingPermissions(
                location: .granted,
                notifications: .granted
            ),
            lastPromptedAt: nil
        )
        let onboardingAPI = MockOnboardingAPI()
        onboardingAPI.getResult = .success(onboardingState)
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(result: .failure(SettingsViewModelMockError.forced)),
            skillsAPI: MockSkillsAPI(result: .success(SkillsResponse(skills: []))),
            onboardingAPI: onboardingAPI,
            cache: TestCacheClient()
        )

        await viewModel.loadOnboarding()

        XCTAssertEqual(viewModel.onboardingState, onboardingState)
        XCTAssertEqual(viewModel.signedInOnboardingRecoveryState, .none)
    }

    func testPermissionRecoveryItemsIncludeMissingLocationAndNotifications() async {
        let onboardingState = OnboardingState(
            status: .dismissed,
            providerReady: true,
            currentOnboardingStep: .permissionRecovery,
            isOnboardingComplete: false,
            intent: .chat,
            milestones: OnboardingMilestones(
                providerConnected: "2026-03-31T12:00:00Z",
                firstOutcomeCompleted: nil,
                profileBasicsSet: nil,
                communicationStyleSet: nil,
                secondaryTourSeen: nil
            ),
            permissions: OnboardingPermissions(
                location: .notAsked,
                notifications: .denied
            ),
            lastPromptedAt: nil
        )
        let onboardingAPI = MockOnboardingAPI()
        onboardingAPI.getResult = .success(onboardingState)
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(result: .failure(SettingsViewModelMockError.forced)),
            skillsAPI: MockSkillsAPI(result: .success(SkillsResponse(skills: []))),
            onboardingAPI: onboardingAPI,
            cache: TestCacheClient()
        )

        await viewModel.loadOnboarding()

        XCTAssertEqual(
            viewModel.permissionRecoveryItems.map(\.kind),
            [.location, .notifications]
        )
        XCTAssertEqual(
            viewModel.permissionRecoveryItems.map(\.actionTitle),
            ["Enable", "Open Settings"]
        )
    }

    func testPermissionRecoveryItemsRemainAvailableInSettingsDuringProviderRecovery() async {
        let onboardingState = OnboardingState(
            status: .dismissed,
            providerReady: false,
            currentOnboardingStep: .providerRecovery,
            isOnboardingComplete: false,
            intent: .chat,
            milestones: OnboardingMilestones(
                providerConnected: nil,
                firstOutcomeCompleted: nil,
                profileBasicsSet: nil,
                communicationStyleSet: nil,
                secondaryTourSeen: nil
            ),
            permissions: OnboardingPermissions(
                location: .notAsked,
                notifications: .denied
            ),
            lastPromptedAt: nil
        )
        let onboardingAPI = MockOnboardingAPI()
        onboardingAPI.getResult = .success(onboardingState)
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(result: .failure(SettingsViewModelMockError.forced)),
            skillsAPI: MockSkillsAPI(result: .success(SkillsResponse(skills: []))),
            onboardingAPI: onboardingAPI,
            cache: TestCacheClient()
        )

        await viewModel.loadOnboarding()

        XCTAssertEqual(viewModel.signedInOnboardingRecoveryState, .providerRecovery)
        XCTAssertEqual(
            viewModel.permissionRecoveryItems.map(\.kind),
            [.location, .notifications]
        )
    }

    func testRequestPermissionRecoveryPersistsGrantedLocationState() async {
        let onboardingAPI = MockOnboardingAPI()
        onboardingAPI.getResult = .success(
            OnboardingState(
                status: .dismissed,
                providerReady: true,
                currentOnboardingStep: .permissionRecovery,
                isOnboardingComplete: false,
                intent: .chat,
                milestones: OnboardingMilestones(
                    providerConnected: "2026-03-31T12:00:00Z",
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
        onboardingAPI.updateResult = .success(
            OnboardingState(
                status: .dismissed,
                providerReady: true,
                currentOnboardingStep: .permissionRecovery,
                isOnboardingComplete: false,
                intent: .chat,
                milestones: OnboardingMilestones(
                    providerConnected: "2026-03-31T12:00:00Z",
                    firstOutcomeCompleted: nil,
                    profileBasicsSet: nil,
                    communicationStyleSet: nil,
                    secondaryTourSeen: nil
                ),
                permissions: OnboardingPermissions(
                    location: .granted,
                    notifications: .notAsked
                ),
                lastPromptedAt: nil
            )
        )
        let locationRequester = MockLocationPermissionRequester()
        locationRequester.currentState = .notAsked
        locationRequester.requestResult = .granted
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(result: .failure(SettingsViewModelMockError.forced)),
            skillsAPI: MockSkillsAPI(result: .success(SkillsResponse(skills: []))),
            onboardingAPI: onboardingAPI,
            locationPermissionRequester: locationRequester,
            notificationPermissionRequester: MockNotificationPermissionRequester(),
            cache: TestCacheClient()
        )

        await viewModel.loadOnboarding()

        await viewModel.requestPermissionRecovery(for: .location)

        XCTAssertEqual(locationRequester.requestCount, 1)
        XCTAssertEqual(onboardingAPI.updates.last?.locationPermission, .granted)
        XCTAssertEqual(viewModel.onboardingState?.permissions.location, .granted)
    }

    func testRefreshPermissionRecoveryStatesSyncsChangedNotificationState() async {
        let notificationsRequester = MockNotificationPermissionRequester()
        notificationsRequester.currentStateValue = .granted
        let onboardingAPI = MockOnboardingAPI()
        onboardingAPI.getResult = .success(
            OnboardingState(
                status: .dismissed,
                providerReady: true,
                currentOnboardingStep: .permissionRecovery,
                isOnboardingComplete: false,
                intent: .chat,
                milestones: OnboardingMilestones(
                    providerConnected: "2026-03-31T12:00:00Z",
                    firstOutcomeCompleted: nil,
                    profileBasicsSet: nil,
                    communicationStyleSet: nil,
                    secondaryTourSeen: nil
                ),
                permissions: OnboardingPermissions(
                    location: .granted,
                    notifications: .denied
                ),
                lastPromptedAt: nil
            )
        )
        onboardingAPI.updateResult = .success(
            OnboardingState(
                status: .dismissed,
                providerReady: true,
                currentOnboardingStep: .permissionRecovery,
                isOnboardingComplete: false,
                intent: .chat,
                milestones: OnboardingMilestones(
                    providerConnected: "2026-03-31T12:00:00Z",
                    firstOutcomeCompleted: nil,
                    profileBasicsSet: nil,
                    communicationStyleSet: nil,
                    secondaryTourSeen: nil
                ),
                permissions: OnboardingPermissions(
                    location: .granted,
                    notifications: .granted
                ),
                lastPromptedAt: nil
            )
        )
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(result: .failure(SettingsViewModelMockError.forced)),
            skillsAPI: MockSkillsAPI(result: .success(SkillsResponse(skills: []))),
            onboardingAPI: onboardingAPI,
            locationPermissionRequester: MockLocationPermissionRequester(),
            notificationPermissionRequester: notificationsRequester,
            cache: TestCacheClient()
        )

        await viewModel.loadOnboarding()

        await viewModel.refreshPermissionRecoveryStates()

        XCTAssertEqual(notificationsRequester.refreshCount, 1)
        XCTAssertEqual(onboardingAPI.updates.last?.notificationsPermission, .granted)
        XCTAssertEqual(viewModel.onboardingState?.permissions.notifications, .granted)
    }

    func testMarkFeatureDiscoverySeenPersistsOnlyCompletionMilestoneAndLetsBackendDeriveCompletion() async {
        let onboardingAPI = MockOnboardingAPI()
        onboardingAPI.getResult = .success(
            OnboardingState(
                status: .dismissed,
                providerReady: true,
                currentOnboardingStep: .featureDiscovery,
                isOnboardingComplete: false,
                intent: .chat,
                milestones: OnboardingMilestones(
                    providerConnected: "2026-04-02T11:00:00Z",
                    firstOutcomeCompleted: nil,
                    profileBasicsSet: nil,
                    communicationStyleSet: nil,
                    secondaryTourSeen: nil
                ),
                permissions: OnboardingPermissions(
                    location: .granted,
                    notifications: .granted
                ),
                lastPromptedAt: nil
            )
        )
        onboardingAPI.updateResult = .success(
            OnboardingState(
                status: .completed,
                providerReady: true,
                currentOnboardingStep: .completed,
                isOnboardingComplete: true,
                intent: .chat,
                milestones: OnboardingMilestones(
                    providerConnected: "2026-04-02T11:00:00Z",
                    firstOutcomeCompleted: nil,
                    profileBasicsSet: nil,
                    communicationStyleSet: nil,
                    secondaryTourSeen: "2026-04-02T11:05:00Z"
                ),
                permissions: OnboardingPermissions(
                    location: .granted,
                    notifications: .granted
                ),
                lastPromptedAt: nil
            )
        )
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(result: .failure(SettingsViewModelMockError.forced)),
            skillsAPI: MockSkillsAPI(result: .success(SkillsResponse(skills: []))),
            onboardingAPI: onboardingAPI,
            cache: TestCacheClient()
        )

        await viewModel.loadOnboarding()
        await viewModel.markFeatureDiscoverySeen()

        XCTAssertNil(onboardingAPI.updates.last?.status)
        XCTAssertNotNil(onboardingAPI.updates.last?.secondaryTourSeen)
        XCTAssertEqual(viewModel.signedInOnboardingRecoveryState, .none)
    }

}

extension SettingsViewModelOnboardingTests {
    func testMarkFeatureDiscoverySeenDismissesOptimisticallyBeforeAPICompletes() async {
        let onboardingAPI = DelayedOnboardingAPI()
        onboardingAPI.getResult = .success(
            OnboardingState(
                status: .dismissed,
                providerReady: true,
                currentOnboardingStep: .featureDiscovery,
                isOnboardingComplete: false,
                intent: .chat,
                milestones: OnboardingMilestones(
                    providerConnected: "2026-04-02T11:00:00Z",
                    firstOutcomeCompleted: nil,
                    profileBasicsSet: nil,
                    communicationStyleSet: nil,
                    secondaryTourSeen: nil
                ),
                permissions: OnboardingPermissions(
                    location: .granted,
                    notifications: .granted
                ),
                lastPromptedAt: nil
            )
        )
        onboardingAPI.updateResult = .success(
            OnboardingState(
                status: .completed,
                providerReady: true,
                currentOnboardingStep: .completed,
                isOnboardingComplete: true,
                intent: .chat,
                milestones: OnboardingMilestones(
                    providerConnected: "2026-04-02T11:00:00Z",
                    firstOutcomeCompleted: nil,
                    profileBasicsSet: nil,
                    communicationStyleSet: nil,
                    secondaryTourSeen: "2026-04-02T11:05:00Z"
                ),
                permissions: OnboardingPermissions(
                    location: .granted,
                    notifications: .granted
                ),
                lastPromptedAt: nil
            )
        )
        onboardingAPI.updateDelayNanoseconds = 200_000_000
        let updateStarted = expectation(description: "onboarding update started")
        onboardingAPI.onUpdateStarted = {
            updateStarted.fulfill()
        }
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(result: .failure(SettingsViewModelMockError.forced)),
            skillsAPI: MockSkillsAPI(result: .success(SkillsResponse(skills: []))),
            onboardingAPI: onboardingAPI,
            cache: TestCacheClient()
        )

        await viewModel.loadOnboarding()
        let task = Task {
            await viewModel.markFeatureDiscoverySeen()
        }

        await fulfillment(of: [updateStarted], timeout: 1.0)

        XCTAssertEqual(viewModel.signedInOnboardingRecoveryState, .none)
        XCTAssertEqual(viewModel.onboardingState?.status, .dismissed)
        XCTAssertNotNil(viewModel.onboardingState?.milestones.secondaryTourSeen)

        await task.value
    }
}
