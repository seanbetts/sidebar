import Foundation

struct RequestExecutionContext {
    let request: URLRequest
    let intent: RequestIntent
}

extension APIClient {
    public func buildRequest(
        _ path: String,
        method: HTTPMethod,
        headers: [String: String] = [:],
        timeoutInterval: TimeInterval? = nil
    ) throws -> URLRequest {
        try buildRequest(
            path,
            method: method.rawValue,
            body: nil,
            headers: headers,
            timeoutInterval: timeoutInterval
        )
    }

    func buildRequestContext(
        _ path: String,
        method: String,
        body: Encodable?,
        headers: [String: String],
        timeoutInterval: TimeInterval?
    ) throws -> RequestExecutionContext {
        let request = try buildRequest(
            path,
            method: method,
            body: body,
            headers: headers,
            timeoutInterval: timeoutInterval
        )
        let intent = resolvedRequestIntent(
            for: request,
            path: path,
            timeoutInterval: timeoutInterval
        )
        return RequestExecutionContext(request: request, intent: intent)
    }

    func buildRequest(
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

    private func resolvedRequestIntent(
        for request: URLRequest,
        path: String,
        timeoutInterval: TimeInterval?
    ) -> RequestIntent {
        if let intent = config.requestIntentProvider?(request) {
            return intent
        }

        let method = HTTPMethod(request.httpMethod ?? "GET")
        return RequestIntent(
            operation: inferredOperation(for: path, method: method),
            path: path,
            method: method,
            requestKind: inferredRequestKind(for: method),
            authRequirement: .required,
            replaySafety: inferredReplaySafety(for: method),
            timeoutClass: inferredTimeoutClass(timeoutInterval)
        )
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

    private func inferredOperation(for path: String, method: HTTPMethod) -> String {
        let trimmedPath = path
            .split(separator: "?", maxSplits: 1)
            .first
            .map(String.init)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if let trimmedPath, !trimmedPath.isEmpty {
            return "\(method.rawValue.lowercased()).\(trimmedPath.replacingOccurrences(of: "/", with: "."))"
        }
        return method.rawValue.lowercased()
    }

    private func inferredRequestKind(for method: HTTPMethod) -> RequestKind {
        switch method {
        case .get, .head, .options:
            return .foregroundRead
        case .post, .put, .patch, .delete, .custom:
            return .foregroundMutation
        }
    }

    private func inferredReplaySafety(for method: HTTPMethod) -> ReplaySafety {
        switch method {
        // Preserve pre-policy 401 retry semantics for implicit callers until
        // explicit RequestIntent metadata is supplied by the call site.
        case .get:
            return .safeToReplayAlways
        case .put, .patch, .delete:
            return .safeToReplayBeforeBodyStarts
        case .head, .options, .post, .custom:
            return .notReplaySafe
        }
    }

    private func inferredTimeoutClass(_ timeoutInterval: TimeInterval?) -> TimeoutClass {
        guard let timeoutInterval, timeoutInterval > 60 else {
            return .standard
        }
        return .long
    }
}
