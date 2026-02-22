import Foundation
import sideBarShared

/// Defines the requirements for SettingsProviding.
public protocol SettingsProviding {
    func getSettings() async throws -> UserSettings
    func updateSettings(_ update: SettingsUpdate) async throws -> UserSettings
    func getProviderKeyStatus(provider: String?) async throws -> ProviderKeyStatusResponse
    func upsertProviderKey(provider: String, apiKey: String) async throws -> ProviderKeyStatusResponse
    func deleteProviderKey(provider: String?) async throws -> ProviderKeyStatusResponse
    func disconnectProviderConsumer(
        provider: String,
        source: ProviderKeyDisconnectSource,
        skillId: String?
    ) async throws -> ProviderKeyDisconnectResponse
    func getShortcutsToken() async throws -> ShortcutsTokenResponse
    func rotateShortcutsToken() async throws -> ShortcutsTokenResponse
    func uploadProfileImage(data: Data, contentType: String, filename: String) async throws
    func getProfileImage() async throws -> Data
    func deleteProfileImage() async throws
}

/// API client for user settings endpoints.
public struct SettingsAPI {
    private let client: APIClient
    private let session: URLSession

    public init(client: APIClient, session: URLSession = APIClient.makeDefaultSession()) {
        self.client = client
        self.session = session
    }

    public func getSettings() async throws -> UserSettings {
        try await client.request("settings")
    }

    public func updateSettings(_ update: SettingsUpdate) async throws -> UserSettings {
        try await client.request("settings", method: "PATCH", body: update)
    }

    public func getProviderKeyStatus(provider: String?) async throws -> ProviderKeyStatusResponse {
        let path = APIClient.path(
            "settings/ai/provider-key",
            queryItems: [URLQueryItem(name: "provider", value: provider)]
        )
        return try await client.request(path)
    }

    public func upsertProviderKey(provider: String, apiKey: String) async throws -> ProviderKeyStatusResponse {
        try await client.request(
            "settings/ai/provider-key",
            method: "PUT",
            body: ProviderKeyUpdate(provider: provider, apiKey: apiKey)
        )
    }

    public func deleteProviderKey(provider: String?) async throws -> ProviderKeyStatusResponse {
        let path = APIClient.path(
            "settings/ai/provider-key",
            queryItems: [URLQueryItem(name: "provider", value: provider)]
        )
        return try await client.request(path, method: "DELETE")
    }

    public func disconnectProviderConsumer(
        provider: String,
        source: ProviderKeyDisconnectSource,
        skillId: String?
    ) async throws -> ProviderKeyDisconnectResponse {
        try await client.request(
            "settings/ai/provider-key/disconnect",
            method: "POST",
            body: ProviderKeyDisconnectRequest(
                provider: provider,
                source: source,
                skillId: skillId
            )
        )
    }

    public func getShortcutsToken() async throws -> ShortcutsTokenResponse {
        try await client.request("settings/shortcuts/pat")
    }

    public func rotateShortcutsToken() async throws -> ShortcutsTokenResponse {
        try await client.request("settings/shortcuts/pat/rotate", method: "POST")
    }

    public func uploadProfileImage(data: Data, contentType: String, filename: String = "profile-image") async throws {
        let url = client.config.baseUrl.appendingPathComponent("settings/profile-image")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(filename, forHTTPHeaderField: "X-Filename")
        if let token = client.config.accessTokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = data
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.unknown
        }
        guard (200...299).contains(http.statusCode) else {
            let errorDecoder = JSONDecoder()
            errorDecoder.keyDecodingStrategy = .convertFromSnakeCase
            let message = APIClient.decodeErrorMessage(data: data, decoder: errorDecoder)
            if let message {
                throw APIClientError.apiError(message)
            }
            throw APIClientError.requestFailed(http.statusCode)
        }
    }

    public func getProfileImage() async throws -> Data {
        try await client.requestData("settings/profile-image")
    }

    public func deleteProfileImage() async throws {
        try await client.requestVoid("settings/profile-image", method: "DELETE")
    }
}

public extension SettingsProviding {
    func disconnectProviderConsumer(
        provider: String,
        source: ProviderKeyDisconnectSource,
        skillId: String?
    ) async throws -> ProviderKeyDisconnectResponse {
        _ = try await deleteProviderKey(provider: provider)
        return ProviderKeyDisconnectResponse(
            provider: provider,
            source: source,
            actions: ProviderKeyDisconnectActions(
                disabledSkillIds: source == .skill ? [skillId].compactMap { $0 } : [],
                detachedAIProvider: source == .aiProvider,
                deletedProviderKey: true
            ),
            remainingConsumers: ProviderKeyDisconnectRemainingConsumers(
                aiProvider: false,
                skillIds: []
            ),
            settings: ProviderKeyDisconnectSettings(
                enabledSkills: [],
                installedStoreSkills: [],
                aiPrimaryProvider: nil
            )
        )
    }
}

extension SettingsAPI: SettingsProviding {}
