import sideBarShared

nonisolated extension ErrorMapping {
    public static func message(for error: AppError) -> String {
        presentation(for: error).message
    }
    public static func presentation(
        for error: Error,
        operation: String,
        requestKind: RequestKind?
    ) -> ErrorPresentationDecision {
        if let appError = error as? AppError {
            return presentation(for: appError)
        }
        if let apiError = error as? APIClientError {
            return presentation(for: apiError, operation: operation, requestKind: requestKind)
        }
        if error is DecodingError {
            return presentation(
                for: AppError(
                    category: .decoding,
                    operation: operation,
                    requestKind: requestKind,
                    retryability: .notRetryable,
                    recommendedSurface: .toast
                )
            )
        }
        if URLRequestErrorClassifier.category(for: error) != nil {
            return presentation(
                for: AppError.classify(
                    operation: operation,
                    requestKind: requestKind,
                    responseStatus: nil,
                    backendMessage: nil,
                    transportError: error
                )
            )
        }
        return ErrorPresentationDecision(
            surface: .toast,
            title: "Something went wrong",
            message: message(for: error)
        )
    }

    public static func presentation(for error: AppError) -> ErrorPresentationDecision {
        if let specialCase = specialCasePresentation(for: error) {
            return specialCase
        }
        if let networkPresentation = networkPresentation(for: error) {
            return networkPresentation
        }
        return fallbackPresentation(for: error)
    }

    private static func presentation(
        for apiError: APIClientError,
        operation: String,
        requestKind: RequestKind?
    ) -> ErrorPresentationDecision {
        switch apiError {
        case .appError(let appError):
            return presentation(for: AppError.classify(error: appError, operation: operation, requestKind: requestKind))
        case .requestFailed(let status):
            return presentation(
                for: AppError.classify(
                    operation: operation,
                    requestKind: requestKind,
                    responseStatus: status,
                    backendMessage: nil,
                    transportError: nil
                )
            )
        case .apiError(let message):
            if isAuthenticationErrorMessage(message) {
                return presentation(
                    for: AppError.classify(
                        operation: operation,
                        requestKind: requestKind,
                        responseStatus: nil,
                        backendMessage: message,
                        transportError: nil
                    )
                )
            }
            return ErrorPresentationDecision(
                surface: .toast,
                title: "Something went wrong",
                message: messageForAPIErrorMessage(message)
            )
        case .missingToken:
            return presentation(
                for: AppError(
                    category: .authentication,
                    operation: operation,
                    requestKind: requestKind,
                    retryability: .userActionRequired,
                    recommendedSurface: .alert
                )
            )
        case .decodingFailed:
            return presentation(
                for: AppError(
                    category: .decoding,
                    operation: operation,
                    requestKind: requestKind,
                    retryability: .notRetryable,
                    recommendedSurface: .toast
                )
            )
        case .invalidUrl, .unknown:
            return ErrorPresentationDecision(
                surface: .toast,
                title: "Something went wrong",
                message: mapAPIError(apiError)
            )
        }
    }

    private static func specialCasePresentation(for error: AppError) -> ErrorPresentationDecision? {
        switch error.category {
        case .payloadTooLarge:
            return ErrorPresentationDecision(
                surface: .inline,
                title: "Attachment too large",
                message: "File too large. Max size is 100MB."
            )
        case .serverBusy:
            return ErrorPresentationDecision(
                surface: .toast,
                title: "Server busy",
                message: "Server is busy right now. Please try again.",
                retryLabel: "Retry"
            )
        default:
            return nil
        }
    }

    private static func networkPresentation(for error: AppError) -> ErrorPresentationDecision? {
        switch error.category {
        case .offline:
            return retryablePresentation(
                surface: error.recommendedSurface,
                title: "No internet connection",
                message: "Network connection failed. Please check your internet."
            )
        case .serverUnreachable:
            return retryablePresentation(
                surface: error.recommendedSurface,
                title: "Server unreachable",
                message: "Could not reach the server. Please try again."
            )
        case .timeout:
            return retryablePresentation(
                surface: error.recommendedSurface,
                title: "Request timed out",
                message: "Server took too long to respond. Please try again."
            )
        case .rateLimited:
            return retryablePresentation(
                surface: error.recommendedSurface,
                title: "Too many requests",
                message: "Please wait a moment and try again."
            )
        case .secureConnection:
            return ErrorPresentationDecision(
                surface: error.recommendedSurface,
                title: "Secure connection failed",
                message: "Unable to verify a secure connection to the server. Please try again shortly. [SEC-CONN]"
            )
        case .requestRejected:
            return ErrorPresentationDecision(
                surface: error.recommendedSurface,
                title: "Request rejected",
                message: "Request was rejected by the server. If this includes attachments, remove one and try again."
            )
        default:
            return nil
        }
    }

    private static func fallbackPresentation(for error: AppError) -> ErrorPresentationDecision {
        switch error.category {
        case .authentication:
            return ErrorPresentationDecision(
                surface: error.recommendedSurface,
                title: "Session expired",
                message: "Session expired. Please sign in again."
            )
        case .permission:
            return ErrorPresentationDecision(
                surface: error.recommendedSurface,
                title: "Permission required",
                message: "You do not have permission to perform this action."
            )
        case .decoding:
            return ErrorPresentationDecision(
                surface: error.recommendedSurface,
                title: "Unexpected response",
                message: "Received invalid data from server."
            )
        case .cancelled:
            return ErrorPresentationDecision(
                surface: error.recommendedSurface,
                title: "Request cancelled",
                message: "Request was interrupted. Please try again."
            )
        case .payloadTooLarge,
             .serverBusy,
             .offline,
             .serverUnreachable,
             .timeout,
             .secureConnection,
             .rateLimited,
             .requestRejected,
             .unknown:
            return ErrorPresentationDecision(
                surface: error.recommendedSurface,
                title: "Something went wrong",
                message: "Unexpected error."
            )
        }
    }

    private static func retryablePresentation(
        surface: RecommendedSurface,
        title: String,
        message: String
    ) -> ErrorPresentationDecision {
        ErrorPresentationDecision(
            surface: surface,
            title: title,
            message: message,
            retryLabel: "Retry"
        )
    }
}
