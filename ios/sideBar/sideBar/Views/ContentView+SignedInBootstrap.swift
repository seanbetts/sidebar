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
        guard environment.authState == .active, environment.isProtectedContentReady else {
            logSignedInBootstrapSkip(
                reason: environment.authState == .active ? "protected_content_not_ready" : "auth_not_active",
                source: source
            )
            return
        }

        guard Self.shouldStartSignedInBootstrap(
            authState: environment.authState,
            isProtectedContentReady: environment.isProtectedContentReady,
            didLoadSettings: didLoadSettings
        ) else {
            logSignedInBootstrapSkip(reason: "already_loaded", source: source)
            return
        }

        didLoadSettings = true
        logSignedInBootstrapStart(source: source)
        Task {
            environment.currentLocationViewModel.startTrackingIfAuthorized()
            await loadSignedInBootstrapSettings()
            await loadSignedInBootstrapOnboarding()
            await loadSignedInBootstrapProfileImage()
            await refreshWeatherIfPossible()
            logSignedInBootstrapEnd(source: source)
        }
    }

    private func logSignedInBootstrapSkip(reason: String, source: String) {
        StartupDebugTrace.log(
            "signed-in.bootstrap.skip",
            details: [
                "auth_state": environment.authState.rawValue,
                "did_load_settings": didLoadSettings ? "true" : "false",
                "protected_ready": environment.isProtectedContentReady ? "true" : "false",
                "reason": reason,
                "source": source
            ]
        )
    }

    private func logSignedInBootstrapStart(source: String) {
        StartupDebugTrace.log(
            "signed-in.bootstrap.start",
            details: [
                "auth_state": environment.authState.rawValue,
                "has_access_token": hasAccessTokenTraceValue,
                "has_authorization_token": hasAuthorizationTokenTraceValue,
                "has_user_id": hasUserIdTraceValue,
                "settings_loaded": settingsLoadedTraceValue,
                "source": source
            ]
        )
    }

    private func loadSignedInBootstrapSettings() async {
        StartupDebugTrace.log(
            "signed-in.bootstrap.settings.start",
            details: [
                "auth_state": environment.authState.rawValue,
                "has_authorization_token": hasAuthorizationTokenTraceValue
            ]
        )
        await environment.settingsViewModel.load(force: true)
        StartupDebugTrace.log(
            "signed-in.bootstrap.settings.end",
            details: [
                "auth_state": environment.authState.rawValue,
                "error": environment.settingsViewModel.errorMessage ?? "<none>",
                "has_authorization_token": hasAuthorizationTokenTraceValue,
                "settings_loaded": settingsLoadedTraceValue
            ]
        )
    }

    private func loadSignedInBootstrapOnboarding() async {
        StartupDebugTrace.log(
            "signed-in.bootstrap.onboarding.start",
            details: ["auth_state": environment.authState.rawValue]
        )
        await environment.settingsViewModel.loadOnboarding(force: true)
        StartupDebugTrace.log(
            "signed-in.bootstrap.onboarding.end",
            details: [
                "auth_state": environment.authState.rawValue,
                "state_loaded": environment.settingsViewModel.onboardingState == nil ? "false" : "true"
            ]
        )
    }

    private func loadSignedInBootstrapProfileImage() async {
        StartupDebugTrace.log(
            "signed-in.bootstrap.profile-image.start",
            details: ["auth_state": environment.authState.rawValue]
        )
        await environment.settingsViewModel.loadProfileImage()
        StartupDebugTrace.log(
            "signed-in.bootstrap.profile-image.end",
            details: [
                "auth_state": environment.authState.rawValue,
                "has_profile_image": environment.settingsViewModel.profileImageData == nil ? "false" : "true"
            ]
        )
    }

    private func logSignedInBootstrapEnd(source: String) {
        StartupDebugTrace.log(
            "signed-in.bootstrap.end",
            details: [
                "auth_state": environment.authState.rawValue,
                "has_authorization_token": hasAuthorizationTokenTraceValue,
                "settings_error": environment.settingsViewModel.errorMessage ?? "<none>",
                "settings_loaded": settingsLoadedTraceValue,
                "source": source
            ]
        )
    }

    private var hasAccessTokenTraceValue: String {
        environment.container.authSession.accessToken == nil ? "false" : "true"
    }

    private var hasAuthorizationTokenTraceValue: String {
        environment.container.authSession.authorizationToken == nil ? "false" : "true"
    }

    private var hasUserIdTraceValue: String {
        environment.container.authSession.userId == nil ? "false" : "true"
    }

    private var settingsLoadedTraceValue: String {
        environment.settingsViewModel.settings == nil ? "false" : "true"
    }
}
