import Foundation
import sideBarShared

nonisolated extension ErrorMapping {
    static func structuredChatStreamPresentation(
        from payload: [String: Any]?,
        rawError: String?,
        fallbackUserMessage: String?
    ) -> ChatStreamErrorPresentation? {
        guard let payload else {
            return nil
        }
        let errorDetails = payload["error_details"] as? [String: Any]
        let rawCategory = payload["category"] as? String
            ?? errorDetails?["category"] as? String
        guard let category = chatStreamCategory(from: rawCategory) else {
            return nil
        }
        let text = structuredChatStreamText(
            for: category,
            fallbackUserMessage: fallbackUserMessage
        )
        let requestID = (payload["request_id"] as? String)?.trimmedOrNil
            ?? (errorDetails?["request_id"] as? String)?.trimmedOrNil
            ?? extractRequestID(from: rawError)
        let isVersionTwo = (payload["version"] as? Int) == 2
        let assistantContext = (payload["assistant_context"] as? [String: Any])
            .flatMap(eventPayloadDetails)
        let assistantExplanation = (payload["assistant_explanation"] as? String)?
            .trimmedOrNil
        return makeChatStreamPresentation(
            category: category,
            title: text.title,
            userMessage: text.userMessage,
            details: isVersionTwo ? nil : eventPayloadDetails(payload) ?? rawError?.trimmedOrNil,
            requestID: requestID,
            isRetryable: payload["retryable"] as? Bool ?? errorDetails?["retryable"] as? Bool,
            assistantContext: assistantContext,
            assistantExplanation: assistantExplanation
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

    private static let fixedStructuredChatStreamText: [
        ChatStreamErrorCategory: (title: String, userMessage: String)
    ] = [
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
            userMessage: "I couldn't finish this response because it needed too many tool steps. " +
                "Try a narrower follow-up."
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
}
