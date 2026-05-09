import Foundation

public extension AppError {
    static func classify(
        error: Error,
        operation: String,
        requestKind: RequestKind?
    ) -> AppError {
        if let appError = error as? AppError {
            return reclassified(appError, operation: operation, requestKind: requestKind)
        }

        if let apiError = error as? APIClientError {
            switch apiError {
            case .appError(let appError):
                return reclassified(appError, operation: operation, requestKind: requestKind)
            case .requestFailed(let status):
                return classify(
                    operation: operation,
                    requestKind: requestKind,
                    responseStatus: status,
                    backendMessage: nil,
                    transportError: nil
                )
            case .apiError(let message):
                return classify(
                    operation: operation,
                    requestKind: requestKind,
                    responseStatus: nil,
                    backendMessage: message,
                    transportError: nil
                )
            case .missingToken:
                return classifiedError(
                    category: .authentication,
                    operation: operation,
                    requestKind: requestKind,
                    retryability: .userActionRequired,
                    recommendedSurface: .alert,
                    extraDiagnostics: ["backendHint": "missing_token"]
                )
            case .decodingFailed:
                return classifiedError(
                    category: .decoding,
                    operation: operation,
                    requestKind: requestKind,
                    retryability: .notRetryable,
                    recommendedSurface: .toast
                )
            case .invalidUrl, .unknown:
                return classifiedError(
                    category: .unknown,
                    operation: operation,
                    requestKind: requestKind,
                    retryability: .notRetryable,
                    recommendedSurface: .toast
                )
            }
        }

        if error is DecodingError {
            return classifiedError(
                category: .decoding,
                operation: operation,
                requestKind: requestKind,
                retryability: .notRetryable,
                recommendedSurface: .toast
            )
        }

        return classify(
            operation: operation,
            requestKind: requestKind,
            responseStatus: nil,
            backendMessage: nil,
            transportError: error
        )
    }

    private static func classifiedError(
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

    private static func reclassified(
        _ appError: AppError,
        operation: String,
        requestKind: RequestKind?
    ) -> AppError {
        var diagnostics = appError.diagnostics
        diagnostics["operation"] = operation
        if let requestKind {
            diagnostics["requestKind"] = requestKind.rawValue
        } else {
            diagnostics.removeValue(forKey: "requestKind")
        }

        return AppError(
            category: appError.category,
            operation: operation,
            requestKind: requestKind,
            retryability: appError.retryability,
            recommendedSurface: appError.recommendedSurface,
            diagnostics: diagnostics
        )
    }
}
