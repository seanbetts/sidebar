import XCTest
@testable import sideBar

final class ChatStreamStructuredErrorMappingTests: XCTestCase {
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
