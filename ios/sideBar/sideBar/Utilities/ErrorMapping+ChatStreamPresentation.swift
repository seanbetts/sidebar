import Foundation
import sideBarShared

nonisolated private struct ChatStreamPresentationRule {
    let matches: Bool
    let category: ChatStreamErrorCategory
    let title: String
    let userMessage: String
}

nonisolated extension ErrorMapping {
    public static func chatStreamPresentation(
        from rawError: String?,
        fallbackUserMessage: String? = nil
    ) -> ChatStreamErrorPresentation {
        let trimmedRaw = rawError?.trimmedOrNil
        let sourceText = [trimmedRaw, fallbackUserMessage?.trimmedOrNil]
            .compactMap { $0?.lowercased() }
            .joined(separator: "\n")
        let requestID = extractRequestID(from: trimmedRaw)

        if let matchedPresentation = matchedChatStreamPresentation(
            sourceText: sourceText,
            details: trimmedRaw,
            requestID: requestID,
            fallbackUserMessage: fallbackUserMessage?.trimmedOrNil
        ) {
            return matchedPresentation
        }
        return fallbackChatStreamPresentation(
            details: trimmedRaw,
            requestID: requestID,
            fallbackUserMessage: fallbackUserMessage?.trimmedOrNil
        )
    }

    public static func chatStreamPresentation(
        fromEventPayload payload: [String: Any]?,
        fallbackUserMessage: String? = nil
    ) -> ChatStreamErrorPresentation {
        let rawError = payload?["error"] as? String
        if let structuredPresentation = structuredChatStreamPresentation(
            from: payload,
            rawError: rawError,
            fallbackUserMessage: fallbackUserMessage?.trimmedOrNil
        ) {
            return structuredPresentation
        }
        return chatStreamPresentation(
            from: rawError,
            fallbackUserMessage: fallbackUserMessage
        )
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

    private static func structuredChatStreamPresentation(
        from payload: [String: Any]?,
        rawError: String?,
        fallbackUserMessage: String?
    ) -> ChatStreamErrorPresentation? {
        guard let payload,
              let errorDetails = payload["error_details"] as? [String: Any],
              let category = chatStreamCategory(from: errorDetails["category"] as? String) else {
            return nil
        }
        let text = structuredChatStreamText(
            for: category,
            fallbackUserMessage: fallbackUserMessage
        )
        let requestID = (errorDetails["request_id"] as? String)?.trimmedOrNil
            ?? extractRequestID(from: rawError)
        return makeChatStreamPresentation(
            category: category,
            title: text.title,
            userMessage: text.userMessage,
            details: eventPayloadDetails(payload) ?? rawError?.trimmedOrNil,
            requestID: requestID,
            isRetryable: errorDetails["retryable"] as? Bool
        )
    }

    private static func chatStreamCategory(from rawCategory: String?) -> ChatStreamErrorCategory? {
        guard let rawCategory = rawCategory?.trimmedOrNil else {
            return nil
        }
        return [
            "provider_billing": .providerBilling,
            "provider_rate_limited": .providerRateLimited,
            "auth_or_permission": .authOrPermission,
            "provider_overloaded": .providerOverloaded,
            "request_timeout": .requestTimeout,
            "context_too_large": .contextTooLarge,
            "transport_failure": .transportFailure,
            "empty_response": .emptyResponse,
            "tool_exhaustion": .toolExhaustion,
            "provider_error": .providerError,
            "user_cancelled": .userCancelled,
            "unknown": .unknown
        ][rawCategory]
    }

    private static func structuredChatStreamText(
        for category: ChatStreamErrorCategory,
        fallbackUserMessage: String?
    ) -> (title: String, userMessage: String) {
        let fallbackRules = fallbackStructuredChatStreamText(fallbackUserMessage: fallbackUserMessage)
        if let text = fallbackRules[category] {
            return text
        }
        return fixedStructuredChatStreamText[category] ?? (
            title: "Response error",
            userMessage: "The response hit an error. Please try again."
        )
    }

    private static let fixedStructuredChatStreamText: [ChatStreamErrorCategory: (title: String, userMessage: String)] = [
        .providerBilling: (
            title: "Provider billing",
            userMessage: "The AI provider account needs billing attention."
        ),
        .providerRateLimited: (
            title: "Rate limited",
            userMessage: "The AI provider is rate limited right now. Please wait a moment and try again."
        ),
        .providerOverloaded: (
            title: "Provider busy",
            userMessage: "The AI provider is busy right now. Please try again in a moment."
        ),
        .emptyResponse: (
            title: "Empty response",
            userMessage: "The AI provider returned an empty response. Please try again."
        ),
        .toolExhaustion: (
            title: "Too many tool steps",
            userMessage: "I couldn't finish this response because it needed too many tool steps. Try a narrower follow-up."
        ),
        .providerError: (
            title: "Provider error",
            userMessage: "The AI provider hit an error. Please try again."
        )
    ]

    private static func fallbackStructuredChatStreamText(
        fallbackUserMessage: String?
    ) -> [ChatStreamErrorCategory: (title: String, userMessage: String)] {
        [
            .authOrPermission: (
                title: "Authentication required",
                userMessage: fallbackUserMessage ?? "Authentication failed for the AI provider."
            ),
            .requestTimeout: (
                title: "Request timed out",
                userMessage: fallbackUserMessage ?? "The request timed out. Please try again."
            ),
            .contextTooLarge: (
                title: "Context too large",
                userMessage: fallbackUserMessage ?? "This request is too large to retry without reducing context."
            ),
            .transportFailure: (
                title: "Network error",
                userMessage: fallbackUserMessage ?? "The network connection was interrupted. Please try again."
            ),
            .userCancelled: (
                title: "Request cancelled",
                userMessage: fallbackUserMessage ?? "The request was cancelled before it completed."
            ),
            .unknown: (
                title: fallbackTitle(for: fallbackUserMessage ?? ""),
                userMessage: fallbackUserMessage ?? "The response hit an error. Please try again."
            )
        ]
    }

    private static func eventPayloadDetails(_ payload: [String: Any]) -> String? {
        if JSONSerialization.isValidJSONObject(payload),
           let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
           let details = String(data: data, encoding: .utf8) {
            return details
        }
        return String(describing: payload)
    }

    private static func makeChatStreamPresentation(
        category: ChatStreamErrorCategory,
        title: String,
        userMessage: String,
        details: String?,
        requestID: String?,
        isRetryable: Bool? = nil
    ) -> ChatStreamErrorPresentation {
        ChatStreamErrorPresentation(
            category: category,
            isRetryable: isRetryable ?? Self.isRetryable(category),
            title: title,
            pillText: title,
            userMessage: userMessage,
            details: details,
            requestID: requestID
        )
    }

    private static func isRetryable(_ category: ChatStreamErrorCategory) -> Bool {
        [
            .providerOverloaded,
            .providerRateLimited,
            .providerError,
            .requestTimeout,
            .transportFailure,
            .emptyResponse
        ].contains(category)
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
}
