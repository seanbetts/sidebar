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
}
