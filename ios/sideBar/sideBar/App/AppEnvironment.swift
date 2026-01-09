import Foundation
import Combine

@MainActor
public final class AppEnvironment: ObservableObject {
    public let container: ServiceContainer
    public let configError: EnvironmentConfigLoadError?

    @Published public private(set) var isAuthenticated: Bool = false
    private var cancellables = Set<AnyCancellable>()

    public init(container: ServiceContainer, configError: EnvironmentConfigLoadError? = nil) {
        self.container = container
        self.configError = configError
        self.isAuthenticated = container.authSession.accessToken != nil

        if let authAdapter = container.authSession as? SupabaseAuthAdapter {
            authAdapter.$accessToken
                .sink { [weak self] _token in
                    self?.refreshAuthState()
                }
                .store(in: &cancellables)
        }
    }

    public func refreshAuthState() {
        isAuthenticated = container.authSession.accessToken != nil
    }
}
