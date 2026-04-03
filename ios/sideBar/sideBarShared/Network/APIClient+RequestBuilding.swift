import Foundation

extension APIClient {
    fileprivate func buildRequest(
        _ path: String,
        method: String,
        body: Encodable?,
        headers: [String: String],
        timeoutInterval: TimeInterval?
    ) throws -> URLRequest {
        let url = try resolvedURL(for: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let timeoutInterval {
            request.timeoutInterval = timeoutInterval
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        applyAppVersionHeader(to: &request)
        if let token = config.accessTokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let body {
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            let encoder = Self.makeEncoder()
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }
        return request
    }

    private func resolvedURL(for path: String) throws -> URL {
        guard let queryIndex = path.firstIndex(of: "?") else {
            return config.baseUrl.appendingPathComponent(path)
        }

        let pathPart = String(path[..<queryIndex])
        let queryPart = String(path[path.index(after: queryIndex)...])
        guard var components = URLComponents(url: config.baseUrl, resolvingAgainstBaseURL: false) else {
            throw APIClientError.invalidUrl
        }

        let trimmedPath = pathPart.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let basePath = components.path
        if basePath.isEmpty {
            components.path = "/\(trimmedPath)"
        } else if basePath.hasSuffix("/") {
            components.path = "\(basePath)\(trimmedPath)"
        } else {
            components.path = "\(basePath)/\(trimmedPath)"
        }

        if let existingQuery = components.percentEncodedQuery, !existingQuery.isEmpty {
            components.percentEncodedQuery = "\(existingQuery)&\(queryPart)"
        } else {
            components.percentEncodedQuery = queryPart
        }

        guard let composedURL = components.url else {
            throw APIClientError.invalidUrl
        }
        return composedURL
    }

    private func applyAppVersionHeader(to request: inout URLRequest) {
        guard request.value(forHTTPHeaderField: AppVersionHeader.fieldName) == nil,
              let appVersion = AppVersionHeader.currentValue() else {
            return
        }
        request.setValue(appVersion, forHTTPHeaderField: AppVersionHeader.fieldName)
    }
}
