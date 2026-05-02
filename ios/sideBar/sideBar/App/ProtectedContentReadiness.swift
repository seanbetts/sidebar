import Foundation

/// Central policy for deciding whether signed-in content can be read or shown.
public struct ProtectedContentReadiness: Equatable {
    public let authState: AuthState
    public let hasAuthorizationToken: Bool
    public let isBiometricUnlockEnabled: Bool
    public let isBiometricUnlocked: Bool

    public init(
        authState: AuthState,
        hasAuthorizationToken: Bool,
        isBiometricUnlockEnabled: Bool,
        isBiometricUnlocked: Bool
    ) {
        self.authState = authState
        self.hasAuthorizationToken = hasAuthorizationToken
        self.isBiometricUnlockEnabled = isBiometricUnlockEnabled
        self.isBiometricUnlocked = isBiometricUnlocked
    }

    public var isAuthenticated: Bool {
        switch authState {
        case .active, .staleRecoverable:
            return true
        case .reauthenticationRequired, .signedOut:
            return false
        }
    }

    public var canAttemptServerRead: Bool {
        authState == .active && hasAuthorizationToken
    }

    public var canShowProtectedContent: Bool {
        isAuthenticated && !requiresBiometricUnlock
    }

    public var requiresBiometricUnlock: Bool {
        isAuthenticated && isBiometricUnlockEnabled && !isBiometricUnlocked
    }
}
