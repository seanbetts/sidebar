import Foundation
import sideBarShared

enum WidgetAPIEnvironmentError: Error, Equatable {
    case notAuthenticated
}

final class WidgetAPIEnvironment {
    let apiClient: APIClient
    let keychain: KeychainAuthStateStore
    private let authRefresher: WidgetAuthRefreshing

    init(
        configLoader: () throws -> EnvironmentConfig = EnvironmentConfig.load,
        keychain: KeychainAuthStateStore = ExtensionAuthStateStoreFactory.makeSharedStore(),
        authRefresher: WidgetAuthRefreshing? = nil
    ) throws {
        guard let initialToken = try keychain.loadAccessToken(), !initialToken.isEmpty else {
            throw WidgetAPIEnvironmentError.notAuthenticated
        }

        let config = try configLoader()
        let resolvedAuthRefresher = authRefresher
            ?? WidgetAuthRefresher(keychain: keychain)
            ?? NoopWidgetAuthRefresher()
        self.keychain = keychain
        self.authRefresher = resolvedAuthRefresher

        self.apiClient = APIClient(
            config: APIClientConfig(
                baseUrl: config.apiBaseUrl,
                accessTokenProvider: {
                    try? keychain.loadAccessToken()
                },
                refreshAuthIfNeeded: {
                    await resolvedAuthRefresher.ensureValidSession(forceRefresh: false)
                }
            )
        )
    }

    func ensureValidAccessToken(forceRefresh: Bool = false) async -> Bool {
        await authRefresher.ensureValidSession(forceRefresh: forceRefresh)
    }
}

private struct NoopWidgetAuthRefresher: WidgetAuthRefreshing {
    func ensureValidSession(forceRefresh: Bool) async -> Bool {
        _ = forceRefresh
        return false
    }
}
