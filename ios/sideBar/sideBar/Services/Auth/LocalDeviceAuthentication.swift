import Foundation
@preconcurrency import LocalAuthentication

struct LocalDeviceAuthenticationFailure: Equatable, Identifiable {
    let id = UUID()
    let message: String
    let showsSettingsAction: Bool
}

enum LocalDeviceAuthenticationResult: Equatable {
    case success
    case cancelled
    case failure(LocalDeviceAuthenticationFailure)
}

protocol LocalDeviceAuthenticating {
    func authenticateForSensitiveAction(reason: String) async -> LocalDeviceAuthenticationResult
}

struct LocalDeviceAuthenticator: LocalDeviceAuthenticating {
    func authenticateForSensitiveAction(reason: String) async -> LocalDeviceAuthenticationResult {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        let currentBiometryName = biometryName(for: context.biometryType)
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            let state = BiometricLockErrorPresentation.unavailableState(
                for: LAError.Code(rawValue: authError?.code ?? -1),
                biometryName: currentBiometryName
            )
            return .failure(LocalDeviceAuthenticationFailure(
                message: state.message,
                showsSettingsAction: state.showsSettingsAction
            ))
        }

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                if success {
                    continuation.resume(returning: .success)
                    return
                }

                guard let laError = error as? LAError else {
                    continuation.resume(returning: .failure(LocalDeviceAuthenticationFailure(
                        message: error?.localizedDescription ?? "Unable to authenticate. Please try again.",
                        showsSettingsAction: false
                    )))
                    return
                }

                switch laError.code {
                case .userCancel, .appCancel, .systemCancel:
                    continuation.resume(returning: .cancelled)
                case .biometryNotAvailable, .biometryNotEnrolled, .passcodeNotSet:
                    let state = BiometricLockErrorPresentation.unavailableState(
                        for: laError.code,
                        biometryName: currentBiometryName
                    )
                    continuation.resume(returning: .failure(LocalDeviceAuthenticationFailure(
                        message: state.message,
                        showsSettingsAction: state.showsSettingsAction
                    )))
                default:
                    let state = BiometricLockErrorPresentation.authenticationState(
                        for: laError.code,
                        biometryName: currentBiometryName
                    )
                    continuation.resume(returning: .failure(LocalDeviceAuthenticationFailure(
                        message: state.message,
                        showsSettingsAction: false
                    )))
                }
            }
        }
    }

    private func biometryName(for biometryType: LABiometryType) -> String {
        switch biometryType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        default:
            return "Biometric Unlock"
        }
    }
}
