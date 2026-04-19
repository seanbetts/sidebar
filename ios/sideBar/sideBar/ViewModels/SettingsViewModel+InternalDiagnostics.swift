import Foundation

@MainActor
extension SettingsViewModel {
    static let internalDiagnosticsRevealTapThreshold = 5

    public var canAccessInternalDiagnostics: Bool {
        settings?.canAccessInternalDiagnostics == true
    }

    public var shouldShowInternalDiagnosticsEntry: Bool {
        canAccessInternalDiagnostics && isInternalDiagnosticsLocallyUnlocked
    }

    public func handleInternalDiagnosticsRevealGesture() {
        guard canAccessInternalDiagnostics else { return }
        internalDiagnosticsRevealTapCount += 1
        guard internalDiagnosticsRevealTapCount >= Self.internalDiagnosticsRevealTapThreshold else { return }
        setInternalDiagnosticsLocallyUnlocked(true)
        internalDiagnosticsRevealTapCount = 0
    }

    func setInternalDiagnosticsLocallyUnlocked(_ unlocked: Bool) {
        isInternalDiagnosticsLocallyUnlocked = unlocked
        userDefaults.set(unlocked, forKey: AppStorageKeys.internalDiagnosticsUnlocked)
    }
}
