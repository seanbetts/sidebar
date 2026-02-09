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
        self.session = APIClient.makeDefaultSession()
    }

    /// Uploads a file to the ingestion API and returns the file ID.
    func uploadFile(data: Data, filename: String, mimeType: String) async throws -> String {
        let sourceFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("share-upload-source-\(UUID().uuidString)")
        try data.write(to: sourceFileURL, options: .atomic)
        defer {
            try? FileManager.default.removeItem(at: sourceFileURL)
        }
        return try await uploadFile(fileURL: sourceFileURL, filename: filename, mimeType: mimeType)
    }

    /// Uploads a file URL to the ingestion API and returns the file ID.
    func uploadFile(fileURL: URL, filename: String, mimeType: String) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: apiClient.config.baseUrl.appendingPathComponent("files"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = apiClient.config.accessTokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let bodyFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("share-upload-body-\(UUID().uuidString)")
        try writeMultipartBody(
            to: bodyFileURL,
            boundary: boundary,
            sourceFileURL: fileURL,
            filename: filename,
            mimeType: mimeType
        )
        defer {
            try? FileManager.default.removeItem(at: bodyFileURL)
        }

        let (responseData, response) = try await session.upload(for: request, fromFile: bodyFileURL)
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

    private func writeMultipartBody(
        to destinationURL: URL,
        boundary: String,
        sourceFileURL: URL,
        filename: String,
        mimeType: String
    ) throws {
        FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: destinationURL)
        defer { try? output.close() }

        try output.write(contentsOf: Data("--\(boundary)\r\n".utf8))
        try output.write(contentsOf: Data("Content-Disposition: form-data; name=\"folder\"\r\n\r\n".utf8))
        try output.write(contentsOf: Data("\r\n".utf8))
        try output.write(contentsOf: Data("--\(boundary)\r\n".utf8))
        try output.write(contentsOf: Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".utf8))
        try output.write(contentsOf: Data("Content-Type: \(mimeType)\r\n\r\n".utf8))

        let input = try FileHandle(forReadingFrom: sourceFileURL)
        defer { try? input.close() }
        while true {
            let chunk = input.readData(ofLength: 1024 * 1024)
            if chunk.isEmpty {
                break
            }
            try output.write(contentsOf: chunk)
        }
        try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
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
            return ExtensionUserMessageCatalog.message(for: .notAuthenticated)
        case .invalidBaseUrl:
            return ExtensionUserMessageCatalog.message(for: .invalidBaseUrl)
        case .invalidSharePayload:
            return ExtensionUserMessageCatalog.message(for: .invalidSharePayload)
        case .unsupportedContentType:
            return ExtensionUserMessageCatalog.message(for: .unsupportedContent)
        case .uploadFailed(let message):
            return ExtensionUserMessageCatalog.uploadFailureMessage(detail: message)
        }
    }
}
