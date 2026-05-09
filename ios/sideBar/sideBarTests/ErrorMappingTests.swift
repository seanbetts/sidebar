import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class ErrorMappingTests: XCTestCase {
    private struct RawLocalizedTestError: LocalizedError {
        var errorDescription: String? {
            "backend stack trace: secret detail"
        }
    }

    func testServerBusyMutationUsesToastPresentationDecision() {
        let appError = AppError.classify(
            operation: "tasks.rename",
            requestKind: .foregroundMutation,
            responseStatus: 503,
            backendMessage: "database request timed out",
            transportError: nil
        )

        let presentation = ErrorMapping.presentation(for: appError)

        XCTAssertEqual(presentation.surface, .toast)
        XCTAssertEqual(presentation.title, "Server busy")
        XCTAssertEqual(presentation.message, "Server is busy right now. Please try again.")
        XCTAssertEqual(presentation.retryLabel, "Retry")
    }

    func testPayloadTooLargeUsesInlinePresentationDecision() {
        let appError = AppError.classify(
            operation: "settings.profileImage.upload",
            requestKind: .multipartUpload,
            responseStatus: 413,
            backendMessage: nil,
            transportError: nil
        )

        let presentation = ErrorMapping.presentation(for: appError)

        XCTAssertEqual(presentation.surface, .inline)
        XCTAssertEqual(presentation.title, "Attachment too large")
        XCTAssertEqual(presentation.message, "File too large. Max size is 100MB.")
        XCTAssertNil(presentation.retryLabel)
    }

    func testMapsOverloadedChatStreamErrorAsRetryable() {
        let presentation = ErrorMapping.chatStreamPresentation(
            from: "{'error': {'type': 'overloaded_error'}}"
        )

        XCTAssertTrue(presentation.isRetryable)
        XCTAssertEqual(presentation.category, .providerOverloaded)
    }

    func testMapsMaximumToolRoundsAsNonRetryable() {
        let presentation = ErrorMapping.chatStreamPresentation(
            from: "maximum tool rounds reached"
        )

        XCTAssertFalse(presentation.isRetryable)
        XCTAssertEqual(presentation.category, .toolExhaustion)
    }

    func testMapsRateLimitedChatStreamErrorAsRetryable() {
        let presentation = ErrorMapping.chatStreamPresentation(
            from: "{'error': {'type': 'rate_limit_error'}}"
        )

        XCTAssertTrue(presentation.isRetryable)
        XCTAssertEqual(presentation.category, .providerRateLimited)
    }

    func testMapsTimedOutChatStreamErrorAsRetryable() {
        let presentation = ErrorMapping.chatStreamPresentation(
            from: URLError(.timedOut).localizedDescription
        )

        XCTAssertTrue(presentation.isRetryable)
        XCTAssertEqual(presentation.category, .requestTimeout)
    }

    func testMapsConnectivityFailureAsRetryable() {
        let presentation = ErrorMapping.chatStreamPresentation(
            from: URLError(.notConnectedToInternet).localizedDescription
        )

        XCTAssertTrue(presentation.isRetryable)
        XCTAssertEqual(presentation.category, .transportFailure)
    }

    func testMapsEmptyResponseAsRetryable() {
        let presentation = ErrorMapping.chatStreamPresentation(
            from: "Assistant response ended before any text was received."
        )

        XCTAssertTrue(presentation.isRetryable)
        XCTAssertEqual(presentation.category, .emptyResponse)
    }

    func testMapsUserCancellationAsNonRetryable() {
        let presentation = ErrorMapping.chatStreamPresentation(
            from: CancellationError().localizedDescription
        )

        XCTAssertFalse(presentation.isRetryable)
        XCTAssertEqual(presentation.category, .userCancelled)
    }

    func testMapsAuthFailureAsNonRetryable() {
        let presentation = ErrorMapping.chatStreamPresentation(
            from: "{'error': {'type': 'authentication_error'}}"
        )

        XCTAssertFalse(presentation.isRetryable)
        XCTAssertEqual(presentation.category, .authOrPermission)
    }

    func testMapsMissingProviderKeyToActionableChatPresentation() {
        let presentation = ErrorMapping.chatStreamPresentation(
            from: "No API key configured for provider 'anthropic'"
        )

        XCTAssertFalse(presentation.isRetryable)
        XCTAssertEqual(presentation.category, .authOrPermission)
        XCTAssertEqual(presentation.title, "API key required")
        XCTAssertEqual(
            presentation.userMessage,
            "Add an API key in Settings to start using chat."
        )
    }

    func testMapsMissingPrimaryProviderToActionableChatPresentation() {
        let presentation = ErrorMapping.chatStreamPresentation(
            from: "No primary AI provider configured for strict BYOK mode"
        )

        XCTAssertFalse(presentation.isRetryable)
        XCTAssertEqual(presentation.category, .authOrPermission)
        XCTAssertEqual(presentation.title, "AI provider required")
        XCTAssertEqual(
            presentation.userMessage,
            "Choose an AI provider in Settings to start using chat."
        )
    }

    func testMapsContextTooLargeAsNonRetryable() {
        let presentation = ErrorMapping.chatStreamPresentation(
            from: "context length exceeded maximum allowed tokens"
        )

        XCTAssertFalse(presentation.isRetryable)
        XCTAssertEqual(presentation.category, .contextTooLarge)
    }

    func testMapsUnknownFailureAsNonRetryable() {
        let presentation = ErrorMapping.chatStreamPresentation(
            from: "provider emitted an unexpected fatal condition"
        )

        XCTAssertFalse(presentation.isRetryable)
        XCTAssertEqual(presentation.category, .unknown)
    }

    func testMapsOverloadedChatStreamErrorToFriendlyPresentation() {
        let rawError = "{'type': 'error', 'error': {'details': None, 'type': " +
            "'overloaded_error', 'message': 'Overloaded'}, 'request_id': 'req_123'}"

        let presentation = ErrorMapping.chatStreamPresentation(from: rawError)

        XCTAssertEqual(presentation.title, "Provider busy")
        XCTAssertEqual(presentation.pillText, "Provider busy")
        XCTAssertEqual(
            presentation.userMessage,
            "The AI provider is busy right now. Please try again in a moment."
        )
        XCTAssertEqual(presentation.requestID, "req_123")
        XCTAssertEqual(presentation.details, rawError)
    }

    func testMapsEmptyProviderResponseChatStreamErrorToFriendlyPresentation() {
        let presentation = ErrorMapping.chatStreamPresentation(
            from: "Google response contained no text and no tool calls"
        )

        XCTAssertEqual(presentation.title, "Empty response")
        XCTAssertEqual(
            presentation.userMessage,
            "The AI provider returned an empty response. Please try again."
        )
    }

    func testUnknownAPIErrorMessageDoesNotExposeRawBackendText() {
        let message = ErrorMapping.message(for: APIClientError.apiError("backend stack trace: secret detail"))
        XCTAssertEqual(message, "Unexpected error.")
    }

    func testUnknownLocalizedErrorFallsBackToGenericMessage() {
        let message = ErrorMapping.message(for: RawLocalizedTestError())
        XCTAssertEqual(message, "Unexpected error.")
    }

    func testMapsAuthErrorDescription() {
        let message = ErrorMapping.message(for: AuthAdapterError.invalidCredentials)
        XCTAssertEqual(message, AuthAdapterError.invalidCredentials.errorDescription)
    }

    func testMapsTypedOfflineAppError() {
        let appError = AppError.classify(
            operation: "tasks.list",
            requestKind: .foregroundRead,
            responseStatus: nil,
            backendMessage: nil,
            transportError: URLError(.notConnectedToInternet)
        )

        XCTAssertEqual(appError.category, .offline)
        XCTAssertEqual(appError.recommendedSurface, .offlineBanner)
        let message = ErrorMapping.message(for: appError)
        XCTAssertEqual(message, "Network connection failed. Please check your internet.")
    }

    func testMapsTypedTimeoutAppError() {
        let appError = AppError.classify(
            operation: "tasks.list",
            requestKind: .foregroundRead,
            responseStatus: nil,
            backendMessage: nil,
            transportError: URLError(.timedOut)
        )

        XCTAssertEqual(appError.category, .timeout)
        XCTAssertEqual(appError.recommendedSurface, .toast)
        let message = ErrorMapping.message(for: appError)
        XCTAssertEqual(message, "Server took too long to respond. Please try again.")
    }

    func testMapsTypedSecureConnectionAppError() {
        let appError = AppError.classify(
            operation: "tasks.list",
            requestKind: .foregroundRead,
            responseStatus: nil,
            backendMessage: nil,
            transportError: URLError(.secureConnectionFailed)
        )

        XCTAssertEqual(appError.category, .secureConnection)
        XCTAssertEqual(appError.recommendedSurface, .alert)
        let message = ErrorMapping.message(for: appError)
        XCTAssertEqual(
            message,
            "Unable to verify a secure connection to the server. Please try again shortly. [SEC-CONN]"
        )
    }

    func testMapsTypedCancelledAppError() {
        let appError = AppError.classify(
            operation: "tasks.list",
            requestKind: .foregroundRead,
            responseStatus: nil,
            backendMessage: nil,
            transportError: URLError(.cancelled)
        )

        XCTAssertEqual(appError.category, .cancelled)
        XCTAssertEqual(appError.recommendedSurface, .silent)
        let message = ErrorMapping.message(for: appError)
        XCTAssertEqual(message, "Request was interrupted. Please try again.")
    }

    func testMapsCancelledRequestWithPeerTrustAsSecureConnectionError() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: URLError.cancelled.rawValue,
            userInfo: [NSURLErrorFailingURLPeerTrustErrorKey: "peer-trust"]
        )
        let message = ErrorMapping.message(for: error)
        XCTAssertEqual(
            message,
            "Unable to verify a secure connection to the server. Please try again shortly. [SEC-CONN]"
        )
    }

    func testMapsCancelledRequestWithRegistryAsCertPinError() {
        let host = "cert-pin-\(UUID().uuidString.lowercased()).example.com"
        CertPinCancellationRegistry.shared.record(host: host)
        let error = URLError(
            .cancelled,
            userInfo: [NSURLErrorFailingURLErrorKey: URL(string: "https://\(host)/v1/test")!]
        )
        let message = ErrorMapping.message(for: error)
        XCTAssertEqual(
            message,
            "Unable to verify a secure connection to the server. Please try again shortly. [SEC-CONN]"
        )
    }

    func testMapsCancelledRequestWithoutRegistryEntryStaysCancelled() {
        // A plain cancellation with no registry entry stays as .cancelled.
        let error = URLError(
            .cancelled,
            userInfo: [NSURLErrorFailingURLErrorKey: URL(string: "https://unknown-host.example.com/v1/test")!]
        )
        let message = ErrorMapping.message(for: error)
        XCTAssertEqual(message, "Request was interrupted. Please try again.")
    }

    func testMapsOperationMessage() {
        let message = ErrorMapping.message(for: APIClientError.invalidUrl, during: "load settings")
        XCTAssertEqual(message, "Failed to load settings: Invalid request URL.")
    }

    func testMapsTypedRequestTimeoutStatus() {
        let appError = AppError.classify(
            operation: "tasks.list",
            requestKind: .foregroundRead,
            responseStatus: 408,
            backendMessage: nil,
            transportError: nil
        )

        XCTAssertEqual(appError.category, .timeout)
        XCTAssertEqual(appError.recommendedSurface, .toast)
        let message = ErrorMapping.message(for: appError)
        XCTAssertEqual(message, "Server took too long to respond. Please try again.")
    }

    func testMapsTypedGatewayTimeoutStatus() {
        let appError = AppError.classify(
            operation: "tasks.list",
            requestKind: .foregroundRead,
            responseStatus: 504,
            backendMessage: nil,
            transportError: nil
        )

        XCTAssertEqual(appError.category, .timeout)
        let message = ErrorMapping.message(for: appError)
        XCTAssertEqual(message, "Server took too long to respond. Please try again.")
    }

    func testMapsTypedServiceUnavailableStatusToBusyServerMessage() {
        let appError = AppError.classify(
            operation: "tasks.list",
            requestKind: .foregroundRead,
            responseStatus: 503,
            backendMessage: nil,
            transportError: nil
        )

        XCTAssertEqual(appError.category, .serverBusy)
        XCTAssertEqual(appError.recommendedSurface, .toast)
        let message = ErrorMapping.message(for: appError)
        XCTAssertEqual(message, "Server is busy right now. Please try again.")
    }

    func testMapsTypedBadRequestStatusToAttachmentGuidance() {
        let appError = AppError.classify(
            operation: "files.upload",
            requestKind: .multipartUpload,
            responseStatus: 400,
            backendMessage: nil,
            transportError: nil
        )

        XCTAssertEqual(appError.category, .requestRejected)
        XCTAssertEqual(appError.recommendedSurface, .toast)
        let message = ErrorMapping.message(for: appError)
        XCTAssertEqual(
            message,
            "Request was rejected by the server. If this includes attachments, remove one and try again."
        )
    }

    func testMapsTypedAuthenticationHintToSessionExpiredMessage() {
        let appError = AppError.classify(
            operation: "chat.send",
            requestKind: .foregroundMutation,
            responseStatus: nil,
            backendMessage: "Not authenticated",
            transportError: nil
        )

        XCTAssertEqual(appError.category, .authentication)
        XCTAssertEqual(appError.recommendedSurface, .alert)
        let message = ErrorMapping.message(for: appError)
        XCTAssertEqual(message, "Session expired. Please sign in again.")
    }

    func testMapsPromptTooLargeApiErrorToHelpfulMessage() {
        let message = ErrorMapping.message(
            for: APIClientError.apiError("System prompt exceeds maximum size (50001 > 40000)")
        )
        XCTAssertEqual(
            message,
            "Attachment and context are too large for one message. Remove some attachments or close open items and try again."
        )
    }

    func testMapsCalibrationPromptConflictToFriendlyMessage() {
        let message = ErrorMapping.message(
            for: APIClientError.apiError("Expected prompt working_relationship")
        )
        XCTAssertEqual(
            message,
            "I got out of sync with your setup. Please go back and try again."
        )
    }

    func testMapsAwaitingNameConflictToFriendlyMessage() {
        let message = ErrorMapping.message(
            for: APIClientError.apiError("Calibration is not awaiting name acceptance")
        )
        XCTAssertEqual(
            message,
            "I got out of sync with your setup. Please go back and try again."
        )
    }

    func testMapsDatabaseRequestTimeoutToBusyServerMessage() {
        let message = ErrorMapping.message(
            for: APIClientError.apiError("Database request timed out")
        )
        XCTAssertEqual(message, "Server is busy right now. Please try again.")
    }

    func testMapsCalibrationGeneratedInvalidJSONToFriendlyMessage() {
        let message = ErrorMapping.message(
            for: APIClientError.apiError("Generated invalid JSON for assistant_identity.boundaries")
        )
        XCTAssertEqual(
            message,
            "I couldn't finish updating my setup just yet. Your answer is saved, please try again."
        )
    }

    func testMapsCalibrationGeneratedInvalidJSONObjectToFriendlyMessage() {
        let message = ErrorMapping.message(
            for: APIClientError.apiError("Generated invalid JSON object for assistant_soul.purpose")
        )
        XCTAssertEqual(
            message,
            "I couldn't finish updating my setup just yet. Your answer is saved, please try again."
        )
    }

    func testMapsTypedAuthenticationAppErrorToSessionExpiredMessage() {
        let appError = AppError.classify(
            operation: "chat.send",
            requestKind: .foregroundMutation,
            responseStatus: 401,
            backendMessage: nil,
            transportError: nil
        )

        XCTAssertEqual(appError.recommendedSurface, .alert)
        XCTAssertEqual(
            ErrorMapping.message(for: appError),
            "Session expired. Please sign in again."
        )
    }
}
