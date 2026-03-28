import XCTest
@testable import sideBar

@MainActor
final class ChatErrorComponentsTests: XCTestCase {
    func testRetryIconAppearsForLatestRetryableAssistantFailure() {
        let presentation = ChatStreamErrorPresentation(
            category: .providerOverloaded,
            isRetryable: true,
            title: "Provider busy",
            pillText: "Provider busy",
            userMessage: "The AI provider is busy right now. Please try again in a moment.",
            details: nil,
            requestID: nil
        )

        XCTAssertTrue(ChatErrorHeaderState(
            presentation: presentation,
            slotState: .latestRetryable
        ).showsRetryButton)
    }

    func testRetryIconHiddenForNonLatestFailure() {
        XCTAssertFalse(ChatErrorHeaderState(
            presentation: .retryableFixture(),
            slotState: .hidden
        ).showsRetryButton)
    }

    func testRetryIconHiddenForNonRetryableFailure() {
        XCTAssertFalse(ChatErrorHeaderState(
            presentation: .nonRetryableFixture(),
            slotState: .latestRetryable
        ).showsRetryButton)
    }

    func testRetryIconShowsLoadingStateAndDisablesTapWhileRetrying() {
        let state = ChatErrorHeaderState(
            presentation: .retryableFixture(),
            slotState: .retrying
        )

        XCTAssertTrue(state.showsRetryButton)
        XCTAssertTrue(state.occupiesRetryActionSlot)
        XCTAssertTrue(state.showsRetryLoadingIndicator)
        XCTAssertFalse(state.isRetryButtonEnabled)
    }

    func testRetryActionInvokesHandlerWhenEnabled() {
        var didRetry = false
        let view = ChatErrorRetryActionView(
            state: ChatErrorHeaderState(
                presentation: .retryableFixture(),
                slotState: .latestRetryable
            ),
            onRetry: { didRetry = true }
        )

        view.performRetryAction()

        XCTAssertTrue(didRetry)
    }

    func testRetryActionDoesNotInvokeHandlerWhenDisabled() {
        var didRetry = false
        let view = ChatErrorRetryActionView(
            state: ChatErrorHeaderState(
                presentation: .retryableFixture(),
                slotState: .retrying
            ),
            onRetry: { didRetry = true }
        )

        view.performRetryAction()

        XCTAssertFalse(didRetry)
    }

    func testMessageRowBuildsRetryHeaderStateForEligibleErrorMessage() {
        let state = ChatMessageRow.retryHeaderState(
            message: retryableErrorMessage,
            retryHeaderSlotState: .latestRetryable
        )

        XCTAssertEqual(state?.presentation.category, .providerOverloaded)
        XCTAssertTrue(state?.occupiesRetryActionSlot == true)
    }

    func testMessageRowDoesNotBuildRetryHeaderStateForNonErrorMessage() {
        XCTAssertNil(
            ChatMessageRow.retryHeaderState(
                message: completeMessage,
                retryHeaderSlotState: .latestRetryable
            )
        )
    }

    func testRetryHeaderSlotStateResolvesLatestRetryableMessage() {
        let slotState = ChatRetryHeaderSlotState.resolve(
            messageID: "assistant-failed",
            latestRetryableAssistantMessageID: "assistant-failed",
            retryInFlightAssistantMessageID: nil
        )

        XCTAssertEqual(slotState, .latestRetryable)
    }

    func testRetryHeaderSlotStateResolvesRetryingMessage() {
        let slotState = ChatRetryHeaderSlotState.resolve(
            messageID: "assistant-failed",
            latestRetryableAssistantMessageID: nil,
            retryInFlightAssistantMessageID: "assistant-failed"
        )

        XCTAssertEqual(slotState, .retrying)
    }
}

private extension ChatStreamErrorPresentation {
    static func retryableFixture() -> ChatStreamErrorPresentation {
        ChatStreamErrorPresentation(
            category: .providerOverloaded,
            isRetryable: true,
            title: "Provider busy",
            pillText: "Provider busy",
            userMessage: "The AI provider is busy right now. Please try again in a moment.",
            details: nil,
            requestID: nil
        )
    }

    static func nonRetryableFixture() -> ChatStreamErrorPresentation {
        ChatStreamErrorPresentation(
            category: .contextTooLarge,
            isRetryable: false,
            title: "Context too large",
            pillText: "Context too large",
            userMessage: "Attachment and context are too large for one message.",
            details: nil,
            requestID: nil
        )
    }
}

private extension ChatRetryHeaderSlotState {
    static let hidden = ChatRetryHeaderSlotState(
        isLatestRetryableFailure: false,
        isRetryingFailure: false
    )

    static let latestRetryable = ChatRetryHeaderSlotState(
        isLatestRetryableFailure: true,
        isRetryingFailure: false
    )

    static let retrying = ChatRetryHeaderSlotState(
        isLatestRetryableFailure: false,
        isRetryingFailure: true
    )
}

private let retryableErrorMessage = Message(
    id: "assistant-failed",
    role: .assistant,
    content: "",
    status: .error,
    toolCalls: nil,
    needsNewline: nil,
    timestamp: "2026-03-28T12:00:00Z",
    error: "The AI provider is busy right now. Please try again in a moment.",
    errorDetails: "{'error': {'type': 'overloaded_error'}}"
)

private let completeMessage = Message(
    id: "assistant-complete",
    role: .assistant,
    content: "Done",
    status: .complete,
    toolCalls: nil,
    needsNewline: nil,
    timestamp: "2026-03-28T12:00:00Z",
    error: nil
)
