import Foundation

enum SignedInBootstrapAction: Equatable {
    case start
    case reset
    case none
}

extension ContentView {
    static func signedInBootstrapAction(
        authState: AuthState,
        isProtectedContentReady: Bool,
        didLoadSettings: Bool
    ) -> SignedInBootstrapAction {
        if shouldResetSignedInBootstrapState(authState: authState) {
            return .reset
        }
        if shouldStartSignedInBootstrap(
            authState: authState,
            isProtectedContentReady: isProtectedContentReady,
            didLoadSettings: didLoadSettings
        ) {
            return .start
        }
        return .none
    }

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

    func triggerSignedInProtectedContentLoadIfNeeded() {
        guard Self.signedInBootstrapAction(
            authState: environment.authState,
            isProtectedContentReady: environment.isProtectedContentReady,
            didLoadSettings: didLoadSettings
        ) == .start else { return }

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

    func resetSignedInBootstrapState() {
        didEnsureInitialPhoneChatInterface = false
        didLoadSettings = false
    }
}
