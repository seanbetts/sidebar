import XCTest
@testable import sideBar

final class ChatStreamStructuredErrorMappingTests: XCTestCase {
    func testStructuredAssistantContextIsNotMappedToVisibleDetails() {
        let explanation = "I couldn't complete this response because OpenAI reported " +
            "that the account needs billing attention."
        let payload: [String: Any] = [
            "type": "error",
            "version": 2,
            "error": "The AI provider account needs billing attention.",
            "category": "provider_billing",
            "retryable": false,
            "request_id": "req_123",
            "assistant_explanation": explanation,
            "assistant_context": [
                "visibility": "assistant_only",
                "provider": "openai",
                "message": "quota exhausted"
            ]
        ]

        let presentation = ErrorMapping.chatStreamPresentation(fromEventPayload: payload)

        XCTAssertEqual(presentation.category, .providerBilling)
        XCTAssertEqual(
            presentation.userMessage,
            "The AI provider account needs billing attention."
        )
        XCTAssertEqual(presentation.requestID, "req_123")
        XCTAssertNil(presentation.details)
        XCTAssertTrue(presentation.assistantContext?.contains("quota exhausted") == true)
        XCTAssertEqual(presentation.assistantExplanation, explanation)
    }

    func testMapsStructuredProviderBillingPayloadBeforeRawFallback() {
        let payload: [String: Any] = [
            "error": "The response hit an error. Please try again.",
            "error_details": [
                "category": "provider_billing",
                "provider": "openai",
                "request_id": "req_123",
                "retryable": false,
                "user_action_required": true
            ]
        ]

        let presentation = ErrorMapping.chatStreamPresentation(fromEventPayload: payload)

        XCTAssertFalse(presentation.isRetryable)
        XCTAssertEqual(presentation.category, .providerBilling)
        XCTAssertEqual(presentation.title, "Provider billing")
        XCTAssertEqual(
            presentation.userMessage,
            "The AI provider account needs billing attention."
        )
        XCTAssertEqual(presentation.requestID, "req_123")
    }

    func testMapsStructuredProviderErrorAsRetryableWhenFlagged() {
        let payload: [String: Any] = [
            "error": "Provider unavailable",
            "error_details": [
                "category": "provider_error",
                "provider": "google",
                "retryable": true,
                "message": "500 INTERNAL"
            ]
        ]

        let presentation = ErrorMapping.chatStreamPresentation(fromEventPayload: payload)

        XCTAssertTrue(presentation.isRetryable)
        XCTAssertEqual(presentation.category, .providerError)
        XCTAssertEqual(presentation.title, "Provider error")
        XCTAssertEqual(
            presentation.userMessage,
            "The AI provider hit an error. Please try again."
        )
    }
}
