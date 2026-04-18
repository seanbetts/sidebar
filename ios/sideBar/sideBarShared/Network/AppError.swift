import Foundation

public struct AppError: Error, Equatable, Sendable {
    public enum Category: String, Equatable, Sendable {
        case authentication
        case permission
        case offline
        case serverUnreachable
        case timeout
        case secureConnection
        case rateLimited
        case serverBusy
        case requestRejected
        case payloadTooLarge
        case decoding
        case cancelled
        case unknown
    }

    public let category: Category
    public let operation: String
    public let requestKind: RequestKind?
    public let retryability: Retryability
    public let recommendedSurface: RecommendedSurface
    public let diagnostics: [String: String]

    public init(
        category: Category,
        operation: String,
        requestKind: RequestKind?,
        retryability: Retryability,
        recommendedSurface: RecommendedSurface,
        diagnostics: [String: String] = [:]
    ) {
        self.category = category
        self.operation = operation
        self.requestKind = requestKind
        self.retryability = retryability
        self.recommendedSurface = recommendedSurface
        self.diagnostics = diagnostics
    }

    public static func classify(
        operation: String,
        requestKind: RequestKind?,
        responseStatus: Int?,
        backendMessage: String?,
        transportError: Error?
    ) -> AppError {
        if let transportError, let classified = classifyTransportError(
            operation: operation,
            requestKind: requestKind,
            error: transportError
        ) {
            return classified
        }

        if let responseStatus {
            return classifyStatus(
                operation: operation,
                requestKind: requestKind,
                status: responseStatus,
                backendMessage: backendMessage
            )
        }

        if let backendMessage, isAuthenticationMessage(backendMessage) {
            return makeError(
                category: .authentication,
                operation: operation,
                requestKind: requestKind,
                retryability: .userActionRequired,
                recommendedSurface: .alert,
                extraDiagnostics: ["backendHint": "authentication"]
            )
        }

        return makeError(
            category: .unknown,
            operation: operation,
            requestKind: requestKind,
            retryability: .notRetryable,
            recommendedSurface: .toast
        )
    }

    private static func classifyStatus(
        operation: String,
        requestKind: RequestKind?,
        status: Int,
        backendMessage: String?
    ) -> AppError {
        switch status {
        case 400:
            return makeError(
                category: .requestRejected,
                operation: operation,
                requestKind: requestKind,
                retryability: .notRetryable,
                recommendedSurface: .toast,
                extraDiagnostics: [
                    "statusCode": String(status),
                    "backendHint": normalizedBackendHint(from: backendMessage)
                ]
            )
        case 401:
            return makeError(
                category: .authentication,
                operation: operation,
                requestKind: requestKind,
                retryability: .userActionRequired,
                recommendedSurface: .alert,
                extraDiagnostics: ["statusCode": String(status)]
            )
        case 403:
            return makeError(
                category: .permission,
                operation: operation,
                requestKind: requestKind,
                retryability: .notRetryable,
                recommendedSurface: .alert,
                extraDiagnostics: ["statusCode": String(status)]
            )
        case 408, 504:
            return makeError(
                category: .timeout,
                operation: operation,
                requestKind: requestKind,
                retryability: .retryable,
                recommendedSurface: .toast,
                extraDiagnostics: ["statusCode": String(status)]
            )
        case 413:
            return makeError(
                category: .payloadTooLarge,
                operation: operation,
                requestKind: requestKind,
                retryability: .notRetryable,
                recommendedSurface: .alert,
                extraDiagnostics: ["statusCode": String(status)]
            )
        case 429:
            return makeError(
                category: .rateLimited,
                operation: operation,
                requestKind: requestKind,
                retryability: .retryable,
                recommendedSurface: .toast,
                extraDiagnostics: ["statusCode": String(status)]
            )
        case 500...:
            return makeError(
                category: .serverBusy,
                operation: operation,
                requestKind: requestKind,
                retryability: .retryable,
                recommendedSurface: .toast,
                extraDiagnostics: ["statusCode": String(status)]
            )
        default:
            return makeError(
                category: .unknown,
                operation: operation,
                requestKind: requestKind,
                retryability: .notRetryable,
                recommendedSurface: .toast,
                extraDiagnostics: ["statusCode": String(status)]
            )
        }
    }

    private static func classifyTransportError(
        operation: String,
        requestKind: RequestKind?,
        error: Error
    ) -> AppError? {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return classifyNonURLTransportError(
                operation: operation,
                requestKind: requestKind,
                error: error
            )
        }

        let code = URLError.Code(rawValue: nsError.code)

        if code == .cancelled, appearsToBeSecureTransportCancellation(nsError) {
            return makeTransportError(
                .secureConnection,
                operation: operation,
                requestKind: requestKind,
                code: nsError.code
            )
        }

        switch code {
        case .notConnectedToInternet, .networkConnectionLost:
            return makeTransportError(.offline, operation: operation, requestKind: requestKind, code: nsError.code)
        case .timedOut:
            return makeTransportError(.timeout, operation: operation, requestKind: requestKind, code: nsError.code)
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return makeTransportError(
                .serverUnreachable,
                operation: operation,
                requestKind: requestKind,
                code: nsError.code
            )
        case .secureConnectionFailed,
             .appTransportSecurityRequiresSecureConnection,
             .serverCertificateHasBadDate,
             .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .clientCertificateRejected,
             .clientCertificateRequired:
            return makeTransportError(.secureConnection, operation: operation, requestKind: requestKind, code: nsError.code)
        case .userAuthenticationRequired, .userCancelledAuthentication:
            return makeTransportError(.authentication, operation: operation, requestKind: requestKind, code: nsError.code)
        case .cancelled:
            return makeTransportError(.cancelled, operation: operation, requestKind: requestKind, code: nsError.code)
        default:
            return makeTransportError(.unknown, operation: operation, requestKind: requestKind, code: nsError.code)
        }
    }

    private static func classifyNonURLTransportError(
        operation: String,
        requestKind: RequestKind?,
        error: Error
    ) -> AppError? {
        guard error is DecodingError else {
            return nil
        }

        return makeError(
            category: .decoding,
            operation: operation,
            requestKind: requestKind,
            retryability: .notRetryable,
            recommendedSurface: .toast
        )
    }

    private static func makeTransportError(
        _ category: Category,
        operation: String,
        requestKind: RequestKind?,
        code: Int
    ) -> AppError {
        makeError(
            category: category,
            operation: operation,
            requestKind: requestKind,
            retryability: retryability(for: category),
            recommendedSurface: recommendedSurface(for: category),
            extraDiagnostics: ["urlErrorCode": String(code)]
        )
    }

    private static func retryability(for category: Category) -> Retryability {
        switch category {
        case .offline:
            return .allowsOfflineHandoff
        case .timeout, .serverUnreachable:
            return .retryable
        case .authentication:
            return .userActionRequired
        case .secureConnection, .cancelled, .unknown, .decoding,
             .permission, .rateLimited, .serverBusy, .requestRejected, .payloadTooLarge:
            return .notRetryable
        }
    }

    private static func recommendedSurface(for category: Category) -> RecommendedSurface {
        switch category {
        case .offline:
            return .offlineBanner
        case .secureConnection, .authentication:
            return .alert
        case .cancelled:
            return .silent
        case .timeout, .serverUnreachable, .unknown, .decoding,
             .permission, .rateLimited, .serverBusy, .requestRejected, .payloadTooLarge:
            return .toast
        }
    }

    private static func makeError(
        category: Category,
        operation: String,
        requestKind: RequestKind?,
        retryability: Retryability,
        recommendedSurface: RecommendedSurface,
        extraDiagnostics: [String: String] = [:]
    ) -> AppError {
        var diagnostics = extraDiagnostics
        diagnostics["category"] = category.rawValue
        diagnostics["operation"] = operation
        diagnostics["retryability"] = retryability.rawValue
        diagnostics["recommendedSurface"] = recommendedSurface.rawValue
        if let requestKind {
            diagnostics["requestKind"] = requestKind.rawValue
        }

        return AppError(
            category: category,
            operation: operation,
            requestKind: requestKind,
            retryability: retryability,
            recommendedSurface: recommendedSurface,
            diagnostics: diagnostics
        )
    }

    private static func normalizedBackendHint(from message: String?) -> String {
        guard let message else {
            return "none"
        }

        if isAuthenticationMessage(message) {
            return "authentication"
        }

        return "generic"
    }

    private static func isAuthenticationMessage(_ message: String) -> Bool {
        let lowered = message.lowercased()
        let signals = [
            "unauthorized",
            "forbidden",
            "not authenticated",
            "invalid token",
            "token expired",
            "session expired"
        ]
        return signals.contains(where: lowered.contains)
    }

    private static func appearsToBeSecureTransportCancellation(_ error: NSError) -> Bool {
        guard error.domain == NSURLErrorDomain,
              error.code == URLError.cancelled.rawValue else {
            return false
        }

        if error.userInfo[NSURLErrorFailingURLPeerTrustErrorKey] != nil {
            return true
        }

        let failingURL =
            (error.userInfo[NSURLErrorFailingURLErrorKey] as? URL)
            ?? (error.userInfo["NSErrorFailingURLKey"] as? URL)
        if let failingURL,
           let host = failingURL.host?.lowercased(),
           CertPinCancellationRegistry.shared.wasCancelled(host: host) {
            return true
        }

        return false
    }
}

extension AppError: LocalizedError {
    public var errorDescription: String? {
        switch category {
        case .authentication:
            return "Session expired. Please sign in again."
        case .permission:
            return "You do not have permission to perform this action."
        case .offline:
            return "Network connection failed. Please check your internet."
        case .serverUnreachable:
            return "Could not reach the server. Please try again."
        case .timeout:
            return "Server took too long to respond. Please try again."
        case .secureConnection:
            return "Unable to verify a secure connection to the server. Please try again shortly. [SEC-CONN]"
        case .rateLimited, .serverBusy:
            return "Server is busy right now. Please try again."
        case .requestRejected:
            return "Request was rejected by the server. If this includes attachments, remove one and try again."
        case .payloadTooLarge:
            return "File too large. Max size is 100MB."
        case .decoding:
            return "Unexpected response from server."
        case .cancelled:
            return "Request was interrupted. Please try again."
        case .unknown:
            return "Unexpected error."
        }
    }
}
