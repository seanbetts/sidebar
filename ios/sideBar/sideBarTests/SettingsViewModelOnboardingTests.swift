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

    func testSignedInRecoveryStateShowsProviderRecoveryWhenSelectedProviderHasNoKey() async {
        let onboardingState = OnboardingState(
            status: .completed,
            providerReady: true,
            currentOnboardingStep: .completed,
            isOnboardingComplete: true,
            intent: .chat,
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
                aiPrimaryProvider: "anthropic",
                aiPrimaryProviderHasKey: false,
                enabledSkills: []
            )
        )

        await viewModel.loadOnboarding()

        XCTAssertEqual(viewModel.onboardingState, onboardingState)
        XCTAssertEqual(viewModel.signedInOnboardingRecoveryState, .providerRecovery)
    }

    func testSignedInRecoveryStateShowsProviderRecoveryWhenNoPrimaryProviderIsConfigured() async {
        let onboardingState = OnboardingState(
            status: .completed,
            providerReady: false,
            currentOnboardingStep: .completed,
            isOnboardingComplete: true,
            intent: .chat,
            milestones: OnboardingMilestones(
                providerConnected: nil,
                firstOutcomeCompleted: nil,
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

        XCTAssertEqual(viewModel.onboardingState, onboardingState)
        XCTAssertEqual(viewModel.signedInOnboardingRecoveryState, .providerRecovery)
    }
}
