import SwiftUI
import LocalAuthentication
import os

// MARK: - BiometricLockView

public struct BiometricLockView: View {
    let onUnlock: () -> Void
    let onOpenSettings: () -> Void
    let onSignOut: () -> Void
    let scenePhase: ScenePhase

    private let logger = Logger(subsystem: "sideBar", category: "Biometrics")

    @State private var isAuthenticating = false
    @State private var errorMessage: String?
    @State private var biometryType: LABiometryType = .none
    @State private var showPasscodeFallback = false
    @State private var showSettingsAction = false
    @State private var hasAttemptedAutoAuth = false
    @State private var userCancelled = false

    public init(
        onUnlock: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onSignOut: @escaping () -> Void,
        scenePhase: ScenePhase
    ) {
        self.onUnlock = onUnlock
        self.onOpenSettings = onOpenSettings
        self.onSignOut = onSignOut
        self.scenePhase = scenePhase
    }

    /// Whether we need to show the fallback UI (error occurred or user cancelled)
    private var showFallbackUI: Bool {
        errorMessage != nil || showPasscodeFallback || userCancelled
    }

    public var body: some View {
        ZStack {
            // Background always visible
            DesignTokens.Colors.background
                .ignoresSafeArea()

            // Only show the fallback UI if there's an error or cancellation.
            if showFallbackUI {
                VStack(spacing: 20) {
                    LoadingIndicatorView(size: LoadingIndicatorSize.hero, variant: .hero)

                    Text("Unlock sideBar")
                        .appFont(.title3Semibold)

                    if let errorMessage {
                        Text(errorMessage)
                            .appFont(.callout)
                            .foregroundStyle(DesignTokens.Colors.error)
                            .multilineTextAlignment(.center)
                    }

                    Button(action: authenticate) {
                        if isAuthenticating {
                            LoadingIndicatorView(size: LoadingIndicatorSize.inline)
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            Text(unlockButtonTitle)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(DesignTokens.Colors.actionPrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isAuthenticating)

                    if showPasscodeFallback {
                        Button {
                            authenticateWithPasscode()
                        } label: {
                            Text("Use Passcode")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }

                    if showSettingsAction {
                        Button {
                            onOpenSettings()
                        } label: {
                            Text("Enable in Settings")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }

                    Button(role: .destructive) {
                        onSignOut()
                    } label: {
                        Text("Sign Out")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .frame(maxWidth: 420)
                .padding(DesignTokens.Spacing.xl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            updateBiometryType()
        }
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            triggerAutoAuthenticateIfNeeded(for: newPhase)
        }
    }

    private var unlockButtonTitle: String {
        switch biometryType {
        case .faceID:
            return "Unlock with Face ID"
        case .touchID:
            return "Unlock with Touch ID"
        default:
            return "Unlock"
        }
    }

    private var biometryName: String {
        switch biometryType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        default:
            return "Biometric Unlock"
        }
    }

    private func triggerAutoAuthenticateIfNeeded(for phase: ScenePhase) {
        guard phase == .active else { return }
        guard !hasAttemptedAutoAuth else { return }
        guard !isAuthenticating else { return }
        hasAttemptedAutoAuth = true
        authenticate()
    }

    private func updateBiometryType() {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        biometryType = context.biometryType
    }

    private func authenticate() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        errorMessage = nil
        showPasscodeFallback = false
        showSettingsAction = false
        userCancelled = false

        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
            isAuthenticating = false
            handleBiometricUnavailable(error: authError)
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Unlock sideBar to continue."
        ) { success, error in
            DispatchQueue.main.async {
                isAuthenticating = false
                if success {
                    logger.notice("Biometric unlock succeeded")
                    Haptics.notification(.success)
                    onUnlock()
                } else if let error = error {
                    logger.error("Biometric unlock failed: \(error.localizedDescription, privacy: .public)")
                    handleAuthenticationError(error)
                } else {
                    logger.error("Biometric unlock failed: unknown error")
                    errorMessage = "Authentication failed."
                    Haptics.notification(.error)
                }
            }
        }
    }

    private func authenticateWithPasscode() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        errorMessage = nil

        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Enter your device passcode."
        ) { success, error in
            DispatchQueue.main.async {
                isAuthenticating = false
                if success {
                    logger.notice("Passcode unlock succeeded")
                    Haptics.notification(.success)
                    onUnlock()
                } else if let error = error {
                    logger.error("Passcode unlock failed: \(error.localizedDescription, privacy: .public)")
                    errorMessage = error.localizedDescription
                    Haptics.notification(.error)
                }
            }
        }
    }

    private func handleBiometricUnavailable(error: NSError?) {
        let code = LAError.Code(rawValue: error?.code ?? -1)
        let state = BiometricLockErrorPresentation.unavailableState(
            for: code,
            biometryName: biometryName
        )
        errorMessage = state.message
        showPasscodeFallback = state.showsPasscodeFallback
        showSettingsAction = state.showsSettingsAction
    }

    private func handleAuthenticationError(_ error: Error) {
        guard let laError = error as? LAError else {
            errorMessage = "Authentication failed. Please try again."
            Haptics.notification(.error)
            return
        }

        switch laError.code {
        case .userCancel:
            userCancelled = true
            errorMessage = nil
        default:
            let state = BiometricLockErrorPresentation.authenticationState(
                for: laError.code,
                biometryName: biometryName
            )
            errorMessage = state.message
            showPasscodeFallback = state.showsPasscodeFallback
            showSettingsAction = state.showsSettingsAction
        }

        if errorMessage != nil {
            Haptics.notification(.error)
        }
    }
}
