import Combine
import Foundation

@MainActor
/// Publishes session token and auth state changes for product-facing observers.
public protocol AuthSessionStateObserving: AnyObject {
    var accessTokenPublisher: AnyPublisher<String?, Never> { get }
    var authStatePublisher: AnyPublisher<AuthState, Never> { get }
}

@MainActor
/// Publishes auth error events and clears recovered auth errors.
public protocol AuthSessionErrorPresenting: AnyObject {
    var authErrorPublisher: AnyPublisher<AuthErrorEvent, Never> { get }
    func clearAuthError()
}

@MainActor
/// Groups the observable auth session capabilities used by app presentation code.
public protocol AuthSessionObserving: AuthSessionStateObserving, AuthSessionErrorPresenting {
}

@MainActor
/// Restores locally persisted auth state for the offline-access window.
public protocol OfflineAccessRestoring: AnyObject {
    var canRestoreOfflineSession: Bool { get }
    @discardableResult
    func restoreOfflineSession() -> Bool
}

@MainActor
/// Exposes sign-in lockout timing so UI can render retry guidance.
public protocol SignInRateLimitStatusProviding: AnyObject {
    var lockoutRemainingSeconds: Int? { get }
}

@MainActor
/// Marks a locally active session as requiring primary sign-in after backend rejection.
public protocol AuthSessionInvalidating: AnyObject {
    func markSessionReauthenticationRequiredAfterAuthorizationFailure()
}

@MainActor
/// Marks rejected auth only when the failed request matches the current session token.
public protocol AuthSessionTokenScopedInvalidating: AnyObject {
    func markSessionReauthenticationRequiredAfterAuthorizationFailure(rejectedToken: String?)
}
