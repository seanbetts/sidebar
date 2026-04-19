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

    func testLoadOnboardingForcesCompletedPresentationDuringUITests() async {
        let originalValue = environmentValue(for: SettingsViewModel.forceCompletedOnboardingUITestEnvironmentKey)
        setEnvironmentValue("1", for: SettingsViewModel.forceCompletedOnboardingUITestEnvironmentKey)
        defer {
            setEnvironmentValue(originalValue, for: SettingsViewModel.forceCompletedOnboardingUITestEnvironmentKey)
        }

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
        viewModel.applySettingsResponse(
            UserSettings(
                userId: "user-1",
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
                aiPrimaryProvider: nil,
                aiPrimaryProviderHasKey: false,
                enabledSkills: []
            )
        )

        await viewModel.loadOnboarding()

        XCTAssertEqual(viewModel.onboardingState?.status, .completed)
        XCTAssertEqual(viewModel.onboardingState?.currentOnboardingStep, .completed)
        XCTAssertEqual(viewModel.onboardingState?.providerReady, true)
        XCTAssertEqual(viewModel.onboardingState?.isOnboardingComplete, true)
        XCTAssertNotNil(viewModel.onboardingState?.milestones.secondaryTourSeen)
        XCTAssertEqual(viewModel.signedInOnboardingRecoveryState, .none)
    }

    func testLoadOnboardingKeepsFeatureDiscoveryWhenBackendHasFirstOutcomeButNoDismissal() async {
        let onboardingState = OnboardingState(
            status: .inProgress,
            providerReady: true,
            currentOnboardingStep: .featureDiscovery,
            isOnboardingComplete: false,
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
        XCTAssertEqual(viewModel.signedInOnboardingRecoveryState, .featureDiscovery)
    }

    func testLoadOnboardingPreservesExistingFeatureDiscoveryStateWhenRefreshFails() async {
        let onboardingState = OnboardingState(
            status: .inProgress,
            providerReady: true,
            currentOnboardingStep: .featureDiscovery,
            isOnboardingComplete: false,
            intent: .chat,
            milestones: OnboardingMilestones(
                providerConnected: "2026-04-04T18:00:00Z",
                firstOutcomeCompleted: nil,
                profileBasicsSet: "2026-04-04T17:50:00Z",
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
        onboardingAPI.getResult = .failure(SettingsViewModelMockError.forced)

        await viewModel.loadOnboarding(force: true)

        XCTAssertEqual(viewModel.onboardingState, onboardingState)
        XCTAssertEqual(viewModel.signedInOnboardingRecoveryState, .featureDiscovery)
    }

}

extension SettingsViewModelOnboardingTests {
    private func environmentValue(for key: String) -> String? {
        guard let cString = getenv(key) else { return nil }
        return String(cString: cString)
    }

    private func setEnvironmentValue(_ value: String?, for key: String) {
        if let value {
            setenv(key, value, 1)
        } else {
            unsetenv(key)
        }
    }
}
