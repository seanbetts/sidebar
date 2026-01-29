import Foundation
import sideBarShared

@MainActor
final class ShareExtensionEnvironment {
    let apiClient: APIClient
    let websitesAPI: WebsitesAPI
    private let session: URLSession

    init() throws {
        let keychain = KeychainAuthStateStore(
            service: AppGroupConfiguration.keychainService,
            accessGroup: AppGroupConfiguration.keychainAccessGroup
        )
        // Validate token exists at init (fail fast if not authenticated)
        guard let initialToken = try keychain.loadAccessToken(), !initialToken.isEmpty else {
            throw ShareExtensionError.notAuthenticated
        }
        let baseUrl = try ShareExtensionEnvironment.apiBaseURL()
        // Use live token provider to get fresh token on each request
        // (in case main app refreshed the token while extension is active)
        let config = APIClientConfig(baseUrl: baseUrl, accessTokenProvider: {
            try? keychain.loadAccessToken()
        })
        self.apiClient = APIClient(config: config)
        self.websitesAPI = WebsitesAPI(client: apiClient)
        self.session = URLSession.shared
    }

    /// Uploads a file to the ingestion API and returns the file ID.
    func uploadFile(data: Data, filename: String, mimeType: String) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: apiClient.config.baseUrl.appendingPathComponent("files"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = apiClient.config.accessTokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"folder\"\r\n\r\n".utf8))
        body.append(Data("\r\n".utf8))
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body

        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ShareExtensionError.uploadFailed("Invalid response")
        }
        guard (200...299).contains(http.statusCode) else {
            if let errorMessage = parseErrorMessage(from: responseData) {
                throw ShareExtensionError.uploadFailed(errorMessage)
            }
            throw ShareExtensionError.uploadFailed("HTTP \(http.statusCode)")
        }

        struct UploadResponse: Codable { let fileId: String }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let uploadResponse = try decoder.decode(UploadResponse.self, from: responseData)
        return uploadResponse.fileId
    }

    private func parseErrorMessage(from data: Data) -> String? {
        struct ErrorResponse: Codable { let error: String? }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(ErrorResponse.self, from: data).error
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
    case unsupportedContentType
    case uploadFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please sign in to sideBar first."
        case .invalidBaseUrl:
            return "Invalid API base URL."
        case .invalidSharePayload:
            return "Could not read the shared content."
        case .unsupportedContentType:
            return "This content type is not supported."
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        }
    }
}
