import Foundation

@MainActor
final class ShareExtensionEnvironment {
    let apiClient: APIClient
    let websitesAPI: WebsitesAPI

    init() throws {
        let keychain = KeychainAuthStateStore(
            service: AppGroupConfiguration.keychainService,
            accessGroup: AppGroupConfiguration.keychainAccessGroup
        )
        guard let token = try keychain.loadAccessToken(), !token.isEmpty else {
            throw ShareExtensionError.notAuthenticated
        }
        let baseUrl = try ShareExtensionEnvironment.apiBaseURL()
        let config = APIClientConfig(baseUrl: baseUrl, accessTokenProvider: { token })
        self.apiClient = APIClient(config: config)
        self.websitesAPI = WebsitesAPI(client: apiClient)
    }

    private static func apiBaseURL() throws -> URL {
        if let override = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let url = URL(string: override) {
            return url
        }
        guard let url = URL(string: "https://sidebar-api.fly.dev/api/v1") else {
            throw ShareExtensionError.invalidBaseUrl
        }
        return url
    }
}

enum ShareExtensionError: LocalizedError {
    case notAuthenticated
    case invalidBaseUrl
    case invalidSharePayload

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please sign in to sideBar first."
        case .invalidBaseUrl:
            return "Invalid API base URL."
        case .invalidSharePayload:
            return "No URL was provided to share."
        }
    }
}
