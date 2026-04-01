import Foundation

@MainActor
extension SettingsViewModel {
    public var signedInOnboardingRecoveryState: OnboardingPresentation.SignedInRecoveryState {
        if requiresPrimaryProviderRecovery {
            return .providerRecovery
        }
        return OnboardingPresentation.signedInRecoveryState(for: onboardingState)
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
