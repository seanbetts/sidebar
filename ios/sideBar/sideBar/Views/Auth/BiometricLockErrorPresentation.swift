import LocalAuthentication

struct BiometricLockErrorState {
    let message: String
    let showsPasscodeFallback: Bool
    let showsSettingsAction: Bool
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
                showsPasscodeFallback: true,
                showsSettingsAction: true
            )
        case .biometryNotEnrolled:
            return BiometricLockErrorState(
                message: "\(biometryName) is not set up. Enable it in Settings.",
                showsPasscodeFallback: true,
                showsSettingsAction: true
            )
        case .passcodeNotSet:
            return BiometricLockErrorState(
                message: "Set a device passcode to use \(biometryName).",
                showsPasscodeFallback: false,
                showsSettingsAction: true
            )
        default:
            return BiometricLockErrorState(
                message: "Biometric authentication is unavailable.",
                showsPasscodeFallback: false,
                showsSettingsAction: false
            )
        }
    }

    static func authenticationState(
        for code: LAError.Code,
        biometryName: String
    ) -> BiometricLockErrorState {
        switch code {
        case .biometryLockout:
            return BiometricLockErrorState(
                message: "Too many failed attempts. Use your device passcode to unlock.",
                showsPasscodeFallback: true,
                showsSettingsAction: false
            )
        case .biometryNotEnrolled, .biometryNotAvailable, .passcodeNotSet:
            return unavailableState(for: code, biometryName: biometryName)
        case .userFallback:
            return BiometricLockErrorState(
                message: "Please use your device passcode.",
                showsPasscodeFallback: true,
                showsSettingsAction: false
            )
        case .authenticationFailed:
            return BiometricLockErrorState(
                message: "\(biometryName) authentication failed. Please try again.",
                showsPasscodeFallback: false,
                showsSettingsAction: false
            )
        default:
            return BiometricLockErrorState(
                message: "Unable to authenticate. Please try again.",
                showsPasscodeFallback: false,
                showsSettingsAction: false
            )
        }
    }
}
