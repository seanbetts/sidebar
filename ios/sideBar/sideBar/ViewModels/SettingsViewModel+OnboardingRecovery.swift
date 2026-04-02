import Foundation

@MainActor
extension SettingsViewModel {
    private static let onboardingTimestampFormatter = ISO8601DateFormatter()

    public var signedInOnboardingRecoveryState: OnboardingPresentation.SignedInRecoveryState {
        if requiresPrimaryProviderRecovery {
            return .providerRecovery
        }
        return OnboardingPresentation.signedInRecoveryState(for: onboardingState)
    }

    public func markFeatureDiscoverySeen() async {
        let timestamp = Self.onboardingTimestampFormatter.string(from: Date())
        if let onboardingAPI {
            do {
                let state = try await onboardingAPI.updateOnboarding(
                    OnboardingUpdate(
                        status: .completed,
                        milestones: OnboardingMilestonesUpdate(
                            secondaryTourSeen: timestamp
                        )
                    )
                )
                setOnboardingState(state)
                return
            } catch {
                // Keep the existing state if the completion sync fails.
            }
        }

        guard let onboardingState else {
            return
        }

        setOnboardingState(
            OnboardingState(
                status: .completed,
                providerReady: onboardingState.providerReady,
                currentOnboardingStep: .completed,
                isOnboardingComplete: true,
                intent: onboardingState.intent,
                milestones: OnboardingMilestones(
                    providerConnected: onboardingState.milestones.providerConnected,
                    firstOutcomeCompleted: onboardingState.milestones.firstOutcomeCompleted,
                    profileBasicsSet: onboardingState.milestones.profileBasicsSet,
                    communicationStyleSet: onboardingState.milestones.communicationStyleSet,
                    secondaryTourSeen: timestamp
                ),
                permissions: onboardingState.permissions,
                lastPromptedAt: onboardingState.lastPromptedAt
            )
        )
    }

    private var requiresPrimaryProviderRecovery: Bool {
        if onboardingState?.providerReady == false {
            return true
        }
        guard let settings else {
            return false
        }
        guard let provider = settings.aiPrimaryProvider?.trimmingCharacters(in: .whitespacesAndNewlines),
              !provider.isEmpty else {
            return true
        }
        return !settings.aiPrimaryProviderHasKey
    }
}
