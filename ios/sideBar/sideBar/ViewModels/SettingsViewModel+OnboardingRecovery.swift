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
        let optimisticState = onboardingState.map {
            completedOnboardingState(from: $0, timestamp: timestamp)
        }

        if let optimisticState {
            setOnboardingState(optimisticState)
        }

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
                // Keep the optimistic completion state if the sync fails.
            }
        }

        guard optimisticState == nil, let onboardingState else {
            return
        }

        setOnboardingState(completedOnboardingState(from: onboardingState, timestamp: timestamp))
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

    private func completedOnboardingState(
        from onboardingState: OnboardingState,
        timestamp: String
    ) -> OnboardingState {
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
    }
}
