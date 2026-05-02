import Foundation
import sideBarShared

nonisolated private struct ChatStreamPresentationRule {
    let matches: Bool
    let category: ChatStreamErrorCategory
    let title: String
    let userMessage: String
}

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

    public static func chatStreamPresentation(
        from rawError: String?,
        fallbackUserMessage: String? = nil
    ) -> ChatStreamErrorPresentation {
        let trimmedRaw = rawError?.trimmedOrNil
        let details = trimmedRaw
        let sourceText = [trimmedRaw, fallbackUserMessage?.trimmedOrNil]
            .compactMap { $0?.lowercased() }
            .joined(separator: "\n")
        let requestID = extractRequestID(from: trimmedRaw)

        if let matchedPresentation = matchedChatStreamPresentation(
            sourceText: sourceText,
            details: details,
            requestID: requestID,
            fallbackUserMessage: fallbackUserMessage?.trimmedOrNil
        ) {
            return matchedPresentation
        }
        return fallbackChatStreamPresentation(
            details: details,
            requestID: requestID,
            fallbackUserMessage: fallbackUserMessage?.trimmedOrNil
        )
    }

    private static func presentation(
        for apiError: APIClientError,
        operation: String,
        requestKind: RequestKind?
    ) -> ErrorPresentationDecision {
        switch apiError {
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

    private static func matchedChatStreamPresentation(
        sourceText: String,
        details: String?,
        requestID: String?,
        fallbackUserMessage: String?
    ) -> ChatStreamErrorPresentation? {
        let matchedRule = retryableChatStreamRules(
            sourceText: sourceText,
            fallbackUserMessage: fallbackUserMessage
        ).first(where: \.matches)
            ?? nonRetryableChatStreamRules(
                sourceText: sourceText,
                fallbackUserMessage: fallbackUserMessage
            ).first(where: \.matches)

        guard let matchedRule else {
            return nil
        }
        return makeChatStreamPresentation(
            category: matchedRule.category,
            title: matchedRule.title,
            userMessage: matchedRule.userMessage,
            details: details,
            requestID: requestID
        )
    }

    private static func retryableChatStreamRules(
        sourceText: String,
        fallbackUserMessage: String?
    ) -> [ChatStreamPresentationRule] {
        [
            ChatStreamPresentationRule(
                matches: sourceText.contains("overloaded_error") || sourceText.contains("overloaded"),
                category: .providerOverloaded,
                title: "Provider busy",
                userMessage: "The AI provider is busy right now. Please try again in a moment."
            ),
            ChatStreamPresentationRule(
                matches: sourceText.contains("rate_limit")
                    || sourceText.contains("rate limited")
                    || sourceText.contains("too many requests"),
                category: .providerRateLimited,
                title: "Rate limited",
                userMessage: "The AI provider is rate limited right now. Please wait a moment and try again."
            ),
            ChatStreamPresentationRule(
                matches: sourceText.contains("no text and no tool calls")
                    || sourceText.contains("empty response")
                    || sourceText.contains("ended before any text was received"),
                category: .emptyResponse,
                title: "Empty response",
                userMessage: "The AI provider returned an empty response. Please try again."
            ),
            ChatStreamPresentationRule(
                matches: sourceText.contains("timed out")
                    || sourceText.contains("timeout")
                    || sourceText.contains("408")
                    || sourceText.contains("504")
                    || sourceText.contains("nsurlerrordomain error -1001")
                    || sourceText.contains("took too long to respond"),
                category: .requestTimeout,
                title: "Request timed out",
                userMessage: fallbackUserMessage ?? "The request timed out. Please try again."
            ),
            ChatStreamPresentationRule(
                matches: sourceText.contains("offline")
                    || sourceText.contains("nsurlerrordomain error -1003")
                    || sourceText.contains("nsurlerrordomain error -1004")
                    || sourceText.contains("nsurlerrordomain error -1005")
                    || sourceText.contains("nsurlerrordomain error -1009")
                    || sourceText.contains("not connected to internet")
                    || sourceText.contains("network connection")
                    || sourceText.contains("could not reach the server")
                    || sourceText.contains("cannot connect to host")
                    || sourceText.contains("cannot find host")
                    || sourceText.contains("connection lost")
                    || sourceText.contains("stream ended unexpectedly")
                    || sourceText.contains("secure connection")
                    || sourceText.contains("tls")
                    || sourceText.contains("ssl"),
                category: .transportFailure,
                title: "Network error",
                userMessage: fallbackUserMessage ?? "The network connection was interrupted. Please try again."
            )
        ]
    }

    private static func nonRetryableChatStreamRules(
        sourceText: String,
        fallbackUserMessage: String?
    ) -> [ChatStreamPresentationRule] {
        [
            ChatStreamPresentationRule(
                matches: sourceText.contains("maximum tool rounds reached"),
                category: .toolExhaustion,
                title: "Too many tool steps",
                userMessage: "I couldn't finish this response because it needed too many tool steps. Try a narrower follow-up."
            ),
            ChatStreamPresentationRule(
                matches: sourceText.contains("no api key configured for provider"),
                category: .authOrPermission,
                title: "API key required",
                userMessage: "Add an API key in Settings to start using chat."
            ),
            ChatStreamPresentationRule(
                matches: sourceText.contains("no primary ai provider configured for strict byok mode"),
                category: .authOrPermission,
                title: "AI provider required",
                userMessage: "Choose an AI provider in Settings to start using chat."
            ),
            ChatStreamPresentationRule(
                matches: sourceText.contains("authentication_error")
                    || sourceText.contains("unauthorized")
                    || sourceText.contains("forbidden")
                    || sourceText.contains("not authenticated")
                    || sourceText.contains("invalid token")
                    || sourceText.contains("permission"),
                category: .authOrPermission,
                title: "Authentication required",
                userMessage: fallbackUserMessage ?? "Authentication failed. Please sign in again."
            ),
            ChatStreamPresentationRule(
                matches: sourceText.contains("context length exceeded")
                    || sourceText.contains("maximum allowed tokens")
                    || sourceText.contains("message context is too large")
                    || sourceText.contains("prompt too large"),
                category: .contextTooLarge,
                title: "Context too large",
                userMessage: fallbackUserMessage ?? "This request is too large to retry without reducing context."
            ),
            ChatStreamPresentationRule(
                matches: sourceText.contains("cancellationerror")
                    || sourceText.contains("cancelled by user")
                    || sourceText.contains("canceled by user")
                    || sourceText.contains("request was interrupted"),
                category: .userCancelled,
                title: "Request cancelled",
                userMessage: fallbackUserMessage ?? "The request was cancelled before it completed."
            )
        ]
    }

    private static func fallbackChatStreamPresentation(
        details: String?,
        requestID: String?,
        fallbackUserMessage: String?
    ) -> ChatStreamErrorPresentation {
        if let fallbackUserMessage {
            return makeChatStreamPresentation(
                category: .unknown,
                title: fallbackTitle(for: fallbackUserMessage),
                userMessage: fallbackUserMessage,
                details: details,
                requestID: requestID
            )
        }
        return makeChatStreamPresentation(
            category: .unknown,
            title: "Response error",
            userMessage: "The response hit an error. Please try again.",
            details: details,
            requestID: requestID
        )
    }

    private static func makeChatStreamPresentation(
        category: ChatStreamErrorCategory,
        title: String,
        userMessage: String,
        details: String?,
        requestID: String?
    ) -> ChatStreamErrorPresentation {
        ChatStreamErrorPresentation(
            category: category,
            isRetryable: isRetryable(category),
            title: title,
            pillText: title,
            userMessage: userMessage,
            details: details,
            requestID: requestID
        )
    }

    private static func isRetryable(_ category: ChatStreamErrorCategory) -> Bool {
        switch category {
        case .providerOverloaded, .providerRateLimited, .requestTimeout, .transportFailure, .emptyResponse:
            return true
        case .userCancelled, .authOrPermission, .contextTooLarge, .toolExhaustion, .unknown:
            return false
        }
    }

    private static func extractRequestID(from rawError: String?) -> String? {
        guard let rawError = rawError?.trimmedOrNil else {
            return nil
        }
        let patterns = [
            "request_id['\\\"]?\\s*[:=]\\s*['\\\"]([^'\\\"]+)['\\\"]",
            "requestId['\\\"]?\\s*[:=]\\s*['\\\"]([^'\\\"]+)['\\\"]"
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let range = NSRange(rawError.startIndex..<rawError.endIndex, in: rawError)
            guard let match = regex.firstMatch(in: rawError, range: range),
                  let captureRange = Range(match.range(at: 1), in: rawError) else {
                continue
            }
            let requestID = String(rawError[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !requestID.isEmpty {
                return requestID
            }
        }
        return nil
    }

    private static func fallbackTitle(for message: String) -> String {
        let lowered = message.lowercased()
        if lowered.contains("unexpectedly") || lowered.contains("interrupted") {
            return "Response interrupted"
        }
        if lowered.contains("empty response") {
            return "Empty response"
        }
        return "Response error"
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
