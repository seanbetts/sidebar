import Combine
import Foundation

/// Publishes session token and auth state changes for product-facing observers.
@MainActor public protocol AuthSessionStateObserving: AnyObject {
    var accessTokenPublisher: AnyPublisher<String?, Never> { get }
    var authStatePublisher: AnyPublisher<AuthState, Never> { get }
}

/// Publishes auth error events and clears recovered auth errors.
@MainActor public protocol AuthSessionErrorPresenting: AnyObject {
    var authErrorPublisher: AnyPublisher<AuthErrorEvent, Never> { get }
    func clearAuthError()
}

/// Groups the observable auth session capabilities used by app presentation code.
@MainActor public protocol AuthSessionObserving: AuthSessionStateObserving, AuthSessionErrorPresenting {
}

/// Restores locally persisted auth state for the offline-access window.
@MainActor public protocol OfflineAccessRestoring: AnyObject {
    var canRestoreOfflineSession: Bool { get }
    @discardableResult
    func restoreOfflineSession() -> Bool
}

/// Exposes sign-in lockout timing so UI can render retry guidance.
@MainActor public protocol SignInRateLimitStatusProviding: AnyObject {
    var lockoutRemainingSeconds: Int? { get }
}

/// Marks a locally active session as requiring primary sign-in after backend rejection.
@MainActor public protocol AuthSessionInvalidating: AnyObject {
    func markSessionReauthenticationRequiredAfterAuthorizationFailure()
}

/// Marks rejected auth only when the failed request matches the current session token.
@MainActor public protocol AuthSessionTokenScopedInvalidating: AnyObject {
    func markSessionReauthenticationRequiredAfterAuthorizationFailure(rejectedToken: String?)
}
