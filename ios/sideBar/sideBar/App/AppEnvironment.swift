import Foundation
import Combine

@MainActor
public final class AppEnvironment: ObservableObject {
    public let container: ServiceContainer

    @Published public private(set) var isAuthenticated: Bool = false

    public init(container: ServiceContainer) {
        self.container = container
        self.isAuthenticated = container.authSession.accessToken != nil
    }

    public func refreshAuthState() {
        isAuthenticated = container.authSession.accessToken != nil
    }
}
