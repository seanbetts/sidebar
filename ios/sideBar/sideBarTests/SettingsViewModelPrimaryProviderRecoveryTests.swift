import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class SettingsPrimaryProviderRecoveryTests: XCTestCase {
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

    func testSignedInRecoveryStatePrefersBackendSoulCalibrationWhenProviderReadyDespiteStaleLocalKeyState() async {
        let onboardingState = OnboardingState(
            status: .inProgress,
            providerReady: true,
            currentOnboardingStep: .soulCalibration,
            isOnboardingComplete: false,
            intent: .chat,
            calibration: .default,
            milestones: OnboardingMilestones(
                providerConnected: "2026-04-04T08:00:00Z",
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
        XCTAssertEqual(viewModel.signedInOnboardingRecoveryState, .soulCalibration)
    }

    func testRefreshProviderRecoveryStateIfNeededReloadsStaleMissingKeyState() async {
        let onboardingState = OnboardingState(
            status: .completed,
            providerReady: true,
            currentOnboardingStep: .completed,
            isOnboardingComplete: true,
            intent: .chat,
            milestones: OnboardingMilestones(
                providerConnected: "2026-04-08T09:00:00Z",
                firstOutcomeCompleted: "2026-04-08T09:15:00Z",
                profileBasicsSet: nil,
                communicationStyleSet: nil,
                secondaryTourSeen: "2026-04-08T09:20:00Z"
            ),
            permissions: OnboardingPermissions(
                location: .granted,
                notifications: .granted
            ),
            lastPromptedAt: nil
        )
        let onboardingAPI = MockOnboardingAPI()
        onboardingAPI.getResult = .success(onboardingState)
        let api = PrimaryProviderSettingsAPI(
            initial: UserSettings(
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
                aiPrimaryProviderHasKey: true,
                aiPrimaryProviderKeyLast4: "1234",
                enabledSkills: []
            )
        )
        let viewModel = SettingsViewModel(
            settingsAPI: api,
            skillsAPI: PrimaryProviderEmptySkillsAPI(),
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
                aiPrimaryProviderKeyLast4: nil,
                enabledSkills: []
            )
        )

        await viewModel.loadOnboarding()

        XCTAssertEqual(viewModel.signedInOnboardingRecoveryState, .providerRecovery)

        await viewModel.refreshProviderRecoveryStateIfNeeded()

        XCTAssertTrue(viewModel.settings?.aiPrimaryProviderHasKey == true)
        XCTAssertEqual(viewModel.settings?.aiPrimaryProviderKeyLast4, "1234")
        XCTAssertEqual(viewModel.signedInOnboardingRecoveryState, .none)
    }
}
