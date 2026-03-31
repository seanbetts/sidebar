import LocalAuthentication

struct BiometricLockErrorState {
    let message: String
    let showsPasscodeFallback: Bool
}

enum BiometricLockErrorPresentation {
    static func unavailableState(
        for code: LAError.Code?,
        biometryName: String
    ) -> BiometricLockErrorState {
        switch code {
        case .biometryNotAvailable:
            return BiometricLockErrorState(
                message: "\(biometryName) is not available on this device.",
                showsPasscodeFallback: true
            )
        case .biometryNotEnrolled:
            return BiometricLockErrorState(
                message: "\(biometryName) is not set up. Enable it in Settings.",
                showsPasscodeFallback: true
            )
        case .passcodeNotSet:
            return BiometricLockErrorState(
                message: "Set a device passcode to use \(biometryName).",
                showsPasscodeFallback: false
            )
        default:
            return BiometricLockErrorState(
                message: "Biometric authentication is unavailable.",
                showsPasscodeFallback: false
            )
        }
    }
}
