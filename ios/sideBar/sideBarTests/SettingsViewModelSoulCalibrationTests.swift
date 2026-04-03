import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class SettingsViewModelSoulCalibrationTests: XCTestCase {
    func testLoadOnboardingStoresSignedInSoulCalibrationRecoveryStateFromBackend() async {
        let onboardingState = OnboardingState(
            status: .inProgress,
            providerReady: true,
            currentOnboardingStep: .soulCalibration,
            isOnboardingComplete: false,
            intent: .chat,
            calibration: .default,
            milestones: OnboardingMilestones(
                providerConnected: "2026-04-02T12:00:00Z",
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

        await viewModel.loadOnboarding()

        XCTAssertEqual(viewModel.onboardingState, onboardingState)
        XCTAssertEqual(viewModel.signedInOnboardingRecoveryState, .soulCalibration)
    }

    func testApplyAssistantSettingsUpdateMergesPartialIdentityFields() async {
        let initialSettings = UserSettings(
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
            assistantIdentity: AssistantIdentitySettings(
                name: "Navigator",
                tone: "Pragmatic and direct.",
                values: nil,
                boundaries: nil
            ),
            assistantIdentityMeta: nil,
            assistantSoul: AssistantSoulSettings(
                purpose: "Help with meaningful progress.",
                operatingPrinciples: nil,
                adaptationPolicy: nil,
                successSignals: nil
            ),
            assistantSoulMeta: nil,
            aiPrimaryProvider: "anthropic",
            aiPrimaryProviderHasKey: true,
            aiPrimaryProviderKeyLast4: "1234",
            enabledSkills: []
        )
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(result: .success(initialSettings)),
            skillsAPI: MockSkillsAPI(result: .success(SkillsResponse(skills: []))),
            onboardingAPI: MockOnboardingAPI(),
            cache: TestCacheClient()
        )
        await viewModel.load(force: true)

        viewModel.applyAssistantSettingsUpdate(
            AssistantSettingsRealtimeUpdate(
                assistantIdentity: AssistantIdentitySettings(
                    name: nil,
                    tone: nil,
                    values: "Clarity, rigor, and honesty.",
                    boundaries: "Never mislead or manipulate."
                ),
                assistantIdentityMeta: nil,
                assistantSoul: nil,
                assistantSoulMeta: nil,
                requiresRefresh: false
            )
        )

        XCTAssertEqual(viewModel.settings?.assistantIdentity?.name, "Navigator")
        XCTAssertEqual(viewModel.settings?.assistantIdentity?.tone, "Pragmatic and direct.")
        XCTAssertEqual(viewModel.settings?.assistantIdentity?.values, "Clarity, rigor, and honesty.")
        XCTAssertEqual(viewModel.settings?.assistantIdentity?.boundaries, "Never mislead or manipulate.")
    }
}
