import SwiftUI
import LocalAuthentication
import os

public struct BiometricLockView: View {
    let onUnlock: () -> Void
    let onSignOut: () -> Void
    let scenePhase: ScenePhase

    private let logger = Logger(subsystem: "sideBar", category: "Biometrics")

    @State private var isAuthenticating = false
    @State private var errorMessage: String?
    @State private var biometryType: LABiometryType = .none
    @State private var showPasscodeFallback = false
    @State private var hasAttemptedAutoAuth = false
    @State private var userCancelled = false

    public init(onUnlock: @escaping () -> Void, onSignOut: @escaping () -> Void, scenePhase: ScenePhase) {
        self.onUnlock = onUnlock
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

            // Only show the card UI if there's an error or fallback needed
            if showFallbackUI {
                VStack(spacing: 20) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)

                    Text("Unlock sideBar")
                        .font(DesignTokens.Typography.title3Semibold)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(DesignTokens.Colors.error)
                            .multilineTextAlignment(.center)
                    }

                    Button(action: authenticate) {
                        if isAuthenticating {
                            ProgressView()
                                .tint(.black)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(unlockButtonTitle)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.white)
                    .foregroundStyle(.black)
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
                .cardStyle()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            updateBiometryType()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Auto-trigger biometric when app becomes active
            if newPhase == .active && !hasAttemptedAutoAuth && !isAuthenticating {
                hasAttemptedAutoAuth = true
                authenticate()
            }
        }
        .task {
            // Initial auto-trigger if app is already active when view appears
            if scenePhase == .active && !hasAttemptedAutoAuth {
                hasAttemptedAutoAuth = true
                authenticate()
            }
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
                    #if os(iOS)
                    triggerHaptic(.success)
                    #endif
                    onUnlock()
                } else if let error = error {
                    logger.error("Biometric unlock failed: \(error.localizedDescription, privacy: .public)")
                    handleAuthenticationError(error)
                } else {
                    logger.error("Biometric unlock failed: unknown error")
                    errorMessage = "Authentication failed."
                    #if os(iOS)
                    triggerHaptic(.error)
                    #endif
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
                    #if os(iOS)
                    triggerHaptic(.success)
                    #endif
                    onUnlock()
                } else if let error = error {
                    logger.error("Passcode unlock failed: \(error.localizedDescription, privacy: .public)")
                    errorMessage = error.localizedDescription
                    #if os(iOS)
                    triggerHaptic(.error)
                    #endif
                }
            }
        }
    }

    private func handleBiometricUnavailable(error: NSError?) {
        let code = LAError.Code(rawValue: error?.code ?? -1)
        switch code {
        case .biometryNotAvailable:
            errorMessage = "\(biometryName) is not available on this device."
        case .biometryNotEnrolled:
            errorMessage = "\(biometryName) is not set up. Enable it in Settings."
        case .passcodeNotSet:
            errorMessage = "Set a device passcode to use \(biometryName)."
        default:
            errorMessage = "Biometric authentication is unavailable."
        }
    }

    private func handleAuthenticationError(_ error: Error) {
        guard let laError = error as? LAError else {
            errorMessage = "Authentication failed. Please try again."
            #if os(iOS)
            triggerHaptic(.error)
            #endif
            return
        }

        switch laError.code {
        case .biometryLockout:
            errorMessage = "Too many failed attempts. Use your device passcode to unlock."
            showPasscodeFallback = true
        case .biometryNotEnrolled:
            errorMessage = "\(biometryName) is not set up. Enable it in Settings."
        case .biometryNotAvailable:
            errorMessage = "\(biometryName) is not available on this device."
        case .userCancel:
            userCancelled = true
            errorMessage = nil
        case .userFallback:
            errorMessage = "Please use your device passcode."
            showPasscodeFallback = true
        case .passcodeNotSet:
            errorMessage = "Set a device passcode to use \(biometryName)."
        case .authenticationFailed:
            errorMessage = "\(biometryName) authentication failed. Please try again."
        default:
            errorMessage = "Unable to authenticate. Please try again."
        }

        if errorMessage != nil {
            #if os(iOS)
            triggerHaptic(.error)
            #endif
        }
    }

    #if os(iOS)
    private func triggerHaptic(_ style: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(style)
    }
    #endif
}
