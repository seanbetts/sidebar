import Foundation

extension SettingsViewModel {
    static let forceCompletedOnboardingUITestEnvironmentKey = "SIDEBAR_UI_TEST_FORCE_COMPLETED_ONBOARDING"

    static func shouldForceCompletedOnboardingForUITests(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment[forceCompletedOnboardingUITestEnvironmentKey] == "1"
    }

    func normalizedOnboardingStateForPresentation(
        _ state: OnboardingState?
    ) -> OnboardingState? {
        guard let state else {
            return nil
        }
        guard Self.shouldForceCompletedOnboardingForUITests() else {
            return state
        }

        let timestamp = state.milestones.secondaryTourSeen ?? Self.onboardingTimestampFormatter.string(from: Date())
        return OnboardingState(
            status: .completed,
            providerReady: true,
            currentOnboardingStep: .completed,
            isOnboardingComplete: true,
            intent: state.intent,
            calibration: state.calibration,
            milestones: OnboardingMilestones(
                providerConnected: state.milestones.providerConnected,
                firstOutcomeCompleted: state.milestones.firstOutcomeCompleted,
                profileBasicsSet: state.milestones.profileBasicsSet,
                communicationStyleSet: state.milestones.communicationStyleSet,
                secondaryTourSeen: timestamp
            ),
            permissions: state.permissions,
            lastPromptedAt: state.lastPromptedAt
        )
    }
}
