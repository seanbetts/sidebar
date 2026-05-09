import Foundation
import os

extension APIClient {
    public func execute(
        _ request: URLRequest,
        intent: RequestIntent
    ) async throws -> (Data, HTTPURLResponse) {
        var request = request
        try await prepareAuthorizationIfNeeded(for: &request, intent: intent)
        return try await executeRequest(
            request,
            intent: intent,
            transport: { request in
                try await self.session.data(for: request)
            }
        )
    }

    public func executeUpload(
        _ request: URLRequest,
        fromFile bodyFileURL: URL,
        intent: RequestIntent,
        emitSuccessNotification: Bool = true
    ) async throws -> (Data, HTTPURLResponse) {
        var request = request
        try await prepareAuthorizationIfNeeded(for: &request, intent: intent)
        return try await executeRequest(
            request,
            intent: intent,
            emitSuccessNotification: emitSuccessNotification,
            transport: { request in
                try await self.session.upload(for: request, fromFile: bodyFileURL)
            }
        )
    }

    public func buildPreparedRequest(
        _ path: String,
        method: HTTPMethod,
        headers: [String: String] = [:],
        intent: RequestIntent
    ) async throws -> URLRequest {
        var request = try buildRequest(
            path,
            method: method,
            headers: headers
        )
        try await prepareAuthorizationIfNeeded(for: &request, intent: intent)
        return request
    }

    public func executeStream(
        _ request: URLRequest,
        intent: RequestIntent
    ) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        var request = request
        try await prepareAuthorizationIfNeeded(for: &request, intent: intent)
        if let url = request.url {
            logger.debug("Request \(request.httpMethod ?? "GET") \(url.absoluteString, privacy: .public)")
        }
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            handleTransportFailure(error, request: request, intent: intent)
            throw error
        }

        let http = try validateHTTPResponse(response, intent: intent)
        guard (200...299).contains(http.statusCode) else {
            throw try await classifyStreamFailure(bytes: bytes, http: http, intent: intent, request: request)
        }

        postSuccessNotification(intent: intent, statusCode: http.statusCode)
        return (bytes, http)
    }

    private func executeRequest(
        _ request: URLRequest,
        intent: RequestIntent,
        emitSuccessNotification: Bool = true,
        transport: (URLRequest) async throws -> (Data, URLResponse)
    ) async throws -> (Data, HTTPURLResponse) {
        let start = Date()
        if let url = request.url {
            logger.debug("Request \(request.httpMethod ?? "GET") \(url.absoluteString, privacy: .public)")
        }

        let (data, response) = try await performTransport(request, intent: intent, transport: transport)
        let http = try validateHTTPResponse(response, intent: intent)
        logger.debug("Response \(http.statusCode) in \(Int(Date().timeIntervalSince(start) * 1000))ms")

        guard (200...299).contains(http.statusCode) else {
            if let retried = try await retryUnauthorizedRequest(
                request,
                data: data,
                statusCode: http.statusCode,
                intent: intent,
                emitSuccessNotification: emitSuccessNotification,
                transport: transport
            ) {
                return retried
            }

            await notifyAuthRejectedIfNeeded(statusCode: http.statusCode, intent: intent, request: request)
            throw classifyHTTPFailure(data: data, statusCode: http.statusCode, intent: intent)
        }

        if emitSuccessNotification {
            postSuccessNotification(intent: intent, statusCode: http.statusCode)
        }
        return (data, http)
    }

    private func executeRequestWithoutAuthRetry(
        _ request: URLRequest,
        intent: RequestIntent,
        emitSuccessNotification: Bool = true,
        transport: (URLRequest) async throws -> (Data, URLResponse)
    ) async throws -> (Data, HTTPURLResponse) {
        let start = Date()
        let (data, response) = try await performTransport(request, intent: intent, transport: transport)
        let http = try validateHTTPResponse(response, intent: intent)
        logger.debug("Response(retry) \(http.statusCode) in \(Int(Date().timeIntervalSince(start) * 1000))ms")

        guard (200...299).contains(http.statusCode) else {
            await notifyAuthRejectedIfNeeded(statusCode: http.statusCode, intent: intent, request: request)
            throw classifyHTTPFailure(data: data, statusCode: http.statusCode, intent: intent)
        }

        if emitSuccessNotification {
            postSuccessNotification(intent: intent, statusCode: http.statusCode)
        }
        return (data, http)
    }

    private func performTransport(
        _ request: URLRequest,
        intent: RequestIntent,
        transport: (URLRequest) async throws -> (Data, URLResponse)
    ) async throws -> (Data, URLResponse) {
        do {
            return try await transport(request)
        } catch {
            handleTransportFailure(error, request: request, intent: intent)
            throw error
        }
    }

    private func handleTransportFailure(
        _ error: Error,
        request: URLRequest,
        intent: RequestIntent
    ) {
        if isCancellationError(error) {
            logCancellation(request)
            return
        }
        logTransportError(error, request: request)
        postFailureNotification(intent: intent, transportError: error)
    }

    private func validateHTTPResponse(
        _ response: URLResponse,
        intent: RequestIntent
    ) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else {
            logger.error("Response failed: non-HTTP response")
            postFailureNotification(intent: intent, statusCode: nil, backendMessage: nil, transportError: nil)
            throw APIClientError.unknown
        }
        return http
    }

    private func prepareAuthorizationIfNeeded(for request: inout URLRequest, intent: RequestIntent) async throws {
        switch intent.authRequirement {
        case .required:
            request.setValue(nil, forHTTPHeaderField: "Authorization")
            if config.accessTokenProvider() == nil {
                _ = await attemptAuthRefreshIfNeeded()
            }
            guard let token = config.accessTokenProvider(), !token.isEmpty else {
                postFailureNotification(intent: intent, statusCode: nil, backendMessage: nil, transportError: nil)
                throw APIClientError.missingToken
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .optional:
            request.setValue(nil, forHTTPHeaderField: "Authorization")
            guard let token = config.accessTokenProvider(), !token.isEmpty else {
                return
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .none:
            request.setValue(nil, forHTTPHeaderField: "Authorization")
        }
    }

    private func retryUnauthorizedRequest(
        _ request: URLRequest,
        data: Data,
        statusCode: Int,
        intent: RequestIntent,
        emitSuccessNotification: Bool,
        transport: (URLRequest) async throws -> (Data, URLResponse)
    ) async throws -> (Data, HTTPURLResponse)? {
        guard statusCode == 401, shouldAttemptAuthRefresh(for: intent) else {
            return nil
        }

        let method = request.httpMethod ?? "GET"
        let url = request.url?.absoluteString ?? "?"
        let hadToken = request.value(forHTTPHeaderField: "Authorization") != nil
        logger.notice("Response 401 for \(method) \(url); hadToken=\(hadToken) retrying auth refresh")

        let refreshed = await attemptAuthRefreshIfNeeded()
        let tokenChanged = shouldRetryWithUpdatedToken(for: request)
        guard tokenChanged || (refreshed && bearerToken(from: request) == nil) else {
            logger.notice("Auth refresh unavailable for \(method) \(url); no retry token available")
            return nil
        }

        logger.notice(
            "Retrying \(method) \(url) after auth refresh; refreshed=\(refreshed) tokenChanged=\(tokenChanged)"
        )
        var retry = request
        if let token = config.accessTokenProvider() {
            retry.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            retry.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        return try await executeRequestWithoutAuthRetry(
            retry,
            intent: intent,
            emitSuccessNotification: emitSuccessNotification,
            transport: transport
        )
    }

    private func classifyHTTPFailure(
        data: Data,
        statusCode: Int,
        intent: RequestIntent
    ) -> APIClientError {
        if let body = String(data: data, encoding: .utf8), !body.isEmpty {
            logger.error("Response body: \(body.prefix(2000), privacy: .private)")
        }
        let decoder = Self.makeDecoder()
        let message = Self.decodeErrorMessage(data: data, decoder: decoder)
        postFailureNotification(intent: intent, statusCode: statusCode, backendMessage: message, transportError: nil)
        return .appError(
            AppError.classify(
                operation: intent.operation,
                requestKind: intent.requestKind,
                responseStatus: statusCode,
                backendMessage: message,
                transportError: nil
            )
        )
    }

    private func classifyStreamFailure(
        bytes: URLSession.AsyncBytes,
        http: HTTPURLResponse,
        intent: RequestIntent,
        request: URLRequest
    ) async throws -> APIClientError {
        let message: String?
        do {
            let data = try await collectBytes(from: bytes)
            message = Self.decodeErrorMessage(data: data, decoder: Self.makeDecoder())
        } catch {
            postFailureNotification(intent: intent, statusCode: http.statusCode, backendMessage: nil, transportError: nil)
            throw error
        }

        postFailureNotification(intent: intent, statusCode: http.statusCode, backendMessage: message, transportError: nil)
        await notifyAuthRejectedIfNeeded(statusCode: http.statusCode, intent: intent, request: request)
        return .appError(
            AppError.classify(
                operation: intent.operation,
                requestKind: intent.requestKind,
                responseStatus: http.statusCode,
                backendMessage: message,
                transportError: nil
            )
        )
    }

    private func collectBytes(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return data
    }

    private func notifyAuthRejectedIfNeeded(statusCode: Int, intent: RequestIntent, request: URLRequest) async {
        guard statusCode == 401, intent.authRequirement == .required else {
            return
        }
        let rejectedToken = bearerToken(from: request)
        if let handleAuthRejectedForToken = config.handleAuthRejectedForToken {
            await handleAuthRejectedForToken(rejectedToken)
        } else {
            await config.handleAuthRejected?()
        }
        NotificationCenter.default.post(
            name: .apiClientAuthenticationRejected,
            object: nil,
            userInfo: [AuthRejectedUserInfoKey.rejectedToken: rejectedToken as Any]
        )
    }
}
