import Foundation

extension ContentView {
    static func shouldStartSignedInBootstrap(
        authState: AuthState,
        isProtectedContentReady: Bool,
        didLoadSettings: Bool
    ) -> Bool {
        authState == .active && isProtectedContentReady && !didLoadSettings
    }

    static func shouldResetSignedInBootstrapState(authState: AuthState) -> Bool {
        switch authState {
        case .reauthenticationRequired, .signedOut:
            return true
        case .active, .staleRecoverable:
            return false
        }
    }

    func triggerSignedInProtectedContentLoadIfNeeded(source: String) {
        _ = source
        guard environment.authState == .active, environment.isProtectedContentReady else { return }

        guard Self.shouldStartSignedInBootstrap(
            authState: environment.authState,
            isProtectedContentReady: environment.isProtectedContentReady,
            didLoadSettings: didLoadSettings
        ) else { return }

        didLoadSettings = true
        Task {
            environment.currentLocationViewModel.startTrackingIfAuthorized()
            await loadSignedInBootstrapSettings()
            await loadSignedInBootstrapOnboarding()
            await loadSignedInBootstrapProfileImage()
            await refreshWeatherIfPossible()
        }
    }

    private func loadSignedInBootstrapSettings() async {
        await environment.settingsViewModel.load(force: true)
    }

    private func loadSignedInBootstrapOnboarding() async {
        await environment.settingsViewModel.loadOnboarding(force: true)
    }

    private func loadSignedInBootstrapProfileImage() async {
        await environment.settingsViewModel.loadProfileImage()
    }
}
