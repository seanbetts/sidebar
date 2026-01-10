import SwiftUI
import LocalAuthentication

public struct BiometricLockView: View {
    let onUnlock: () -> Void
    let onSignOut: () -> Void

    @State private var isAuthenticating = false
    @State private var errorMessage: String?
    @State private var biometryType: LABiometryType = .none

    public init(onUnlock: @escaping () -> Void, onSignOut: @escaping () -> Void) {
        self.onUnlock = onUnlock
        self.onSignOut = onSignOut
    }

    public var body: some View {
        VStack(spacing: 20) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)

            Text("Unlock sideBar")
                .font(.title3.weight(.semibold))

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            } else {
                Text("Authenticate to continue.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button(action: authenticate) {
                if isAuthenticating {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text(unlockButtonTitle)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isAuthenticating)

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
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .onAppear {
            updateBiometryType()
            authenticate()
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

    private func updateBiometryType() {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        biometryType = context.biometryType
    }

    private func authenticate() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        errorMessage = nil

        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Unlock sideBar to continue."
        ) { success, error in
            DispatchQueue.main.async {
                isAuthenticating = false
                if success {
                    onUnlock()
                } else if let error = error {
                    errorMessage = error.localizedDescription
                } else {
                    errorMessage = "Authentication failed."
                }
            }
        }
    }
}
