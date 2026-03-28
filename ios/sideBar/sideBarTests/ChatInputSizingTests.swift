import XCTest
@testable import sideBar

final class ChatInputSizingTests: XCTestCase {
    func testResolveUsesMinimumHeightWhenContentIsSmall() {
        let sizing = ChatInputSizing.resolve(contentHeight: 24, minHeight: 46, maxHeight: 140)

        XCTAssertEqual(sizing.measuredHeight, 46)
        XCTAssertFalse(sizing.isOverflowing)
    }

    func testResolveUsesContentHeightWhenWithinBounds() {
        let sizing = ChatInputSizing.resolve(contentHeight: 96, minHeight: 46, maxHeight: 140)

        XCTAssertEqual(sizing.measuredHeight, 96)
        XCTAssertFalse(sizing.isOverflowing)
    }

    func testResolveClampsToMaximumHeightAndOverflowsWhenNeeded() {
        let sizing = ChatInputSizing.resolve(contentHeight: 220, minHeight: 46, maxHeight: 140)

        XCTAssertEqual(sizing.measuredHeight, 140)
        XCTAssertTrue(sizing.isOverflowing)
    }

    func testStateMeasuredHeightCollapsesMinimumHeightToZero() {
        XCTAssertEqual(ChatInputSizing.stateMeasuredHeight(for: 46, minHeight: 46), 0)
        XCTAssertEqual(ChatInputSizing.stateMeasuredHeight(for: 24, minHeight: 46), 0)
    }

    func testStateMeasuredHeightPreservesExpandedHeight() {
        XCTAssertEqual(ChatInputSizing.stateMeasuredHeight(for: 59, minHeight: 46), 59)
    }

    func testTextViewStaysEditableWhileFocusedEvenWhenDisabled() {
        XCTAssertTrue(
            ChatInputInteractivity.textViewIsEditable(
                isEnabled: false,
                isFirstResponder: true
            )
        )
    }

    func testTextViewDisablesWhenNotFocusedAndDisabled() {
        XCTAssertFalse(
            ChatInputInteractivity.textViewIsEditable(
                isEnabled: false,
                isFirstResponder: false
            )
        )
    }

    func testTextViewIsEditableWhenEnabled() {
        XCTAssertTrue(
            ChatInputInteractivity.textViewIsEditable(
                isEnabled: true,
                isFirstResponder: false
            )
        )
    }

    func testDeferredHeightStateSchedulesOnlyOnePendingUpdatePerTarget() {
        var state = ChatInputDeferredHeightState()

        XCTAssertTrue(state.shouldSchedule(currentMeasuredHeight: 0, targetMeasuredHeight: 46))
        XCTAssertFalse(state.shouldSchedule(currentMeasuredHeight: 0, targetMeasuredHeight: 46))
        XCTAssertEqual(state.pendingMeasuredHeight, 46)
    }

    func testDeferredHeightStateClearsPendingTargetAfterApply() {
        var state = ChatInputDeferredHeightState()

        XCTAssertTrue(state.shouldSchedule(currentMeasuredHeight: 0, targetMeasuredHeight: 46))
        state.didApply(measuredHeight: 46)

        XCTAssertNil(state.pendingMeasuredHeight)
        XCTAssertFalse(state.shouldSchedule(currentMeasuredHeight: 46, targetMeasuredHeight: 46))
    }

    func testDeferredHeightStateAllowsNewTargetWhileAnotherIsPending() {
        var state = ChatInputDeferredHeightState()

        XCTAssertTrue(state.shouldSchedule(currentMeasuredHeight: 0, targetMeasuredHeight: 46))
        XCTAssertTrue(state.shouldSchedule(currentMeasuredHeight: 0, targetMeasuredHeight: 72))
        XCTAssertEqual(state.pendingMeasuredHeight, 72)
    }
}
