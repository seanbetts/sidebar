import Foundation

public struct SettingsAPI {
    private let client: APIClient
    private let session: URLSession

    public init(client: APIClient, session: URLSession = .shared) {
        self.client = client
        self.session = session
    }

    public func getSettings() async throws -> UserSettings {
        try await client.request("settings")
    }

    public func updateSettings(_ update: SettingsUpdate) async throws -> UserSettings {
        try await client.request("settings", method: "PATCH", body: update)
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
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIClientError.requestFailed((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    public func getProfileImage() async throws -> Data {
        let url = client.config.baseUrl.appendingPathComponent("settings/profile-image")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = client.config.accessTokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIClientError.requestFailed((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
    }

    public func deleteProfileImage() async throws {
        try await client.requestVoid("settings/profile-image", method: "DELETE")
    }
}
