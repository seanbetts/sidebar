import Combine
import Foundation

extension SupabaseAuthAdapter: AuthSessionObserving, OfflineAccessRestoring, SignInRateLimitStatusProviding {
    public var accessTokenPublisher: AnyPublisher<String?, Never> {
        $accessToken.eraseToAnyPublisher()
    }

    public var authStatePublisher: AnyPublisher<AuthState, Never> {
        $authState.eraseToAnyPublisher()
    }

    public var authErrorPublisher: AnyPublisher<AuthErrorEvent, Never> {
        $authError
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }
}
