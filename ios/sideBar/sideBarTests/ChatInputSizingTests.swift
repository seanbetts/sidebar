import XCTest
@testable import sideBar

@MainActor
final class ChatInputSizingTests: XCTestCase {
    func testChatInputUsesSharedFieldChrome() {
        XCTAssertEqual(ChatInputBar.chromeKind, .field)
    }

    func testUIKitAccessoryButtonsUsePlainSymbolsInsideFieldChrome() throws {
        let normalized = try chatInputSource(named: "ChatInputUIKit.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("systemName:\"paperclip\""))
        XCTAssertTrue(normalized.contains("systemName:\"arrow.up\""))
        XCTAssertFalse(normalized.contains("paperclip.circle.fill"))
        XCTAssertFalse(normalized.contains("arrow.up.circle.fill"))
    }

    func testAppKitAccessoryButtonsUsePlainSymbolsInsideFieldChrome() throws {
        let normalized = try chatInputSource(named: "ChatInputAppKit.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("systemSymbolName:\"paperclip\""))
        XCTAssertTrue(normalized.contains("systemSymbolName:\"arrow.up\""))
        XCTAssertFalse(normalized.contains("paperclip.circle.fill"))
        XCTAssertFalse(normalized.contains("arrow.up.circle.fill"))
    }

    func testChatInputAccessoryButtonsUseSharedCompactTouchTargets() throws {
        let uiKitSource = try chatInputSource(named: "ChatInputUIKit.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let appKitSource = try chatInputSource(named: "ChatInputAppKit.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            uiKitSource.contains("privatevarsideButtonSize:CGFloat=HeaderActionControlMetrics.iconFrameHeight")
        )
        XCTAssertTrue(
            appKitSource.contains("privatevarsideButtonSize:CGFloat=HeaderActionControlMetrics.iconFrameHeight")
        )
    }

    func testChatInputChromeMetricsUseAppTextSizeHelpersInsteadOfScaledMetric() throws {
        let uiKitSource = try (
            chatInputSource(named: "ChatInputUIKit.swift")
                + chatInputSource(named: "ChatInputUIKit+Metrics.swift")
        )
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let appKitSource = try chatInputSource(named: "ChatInputAppKit.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(uiKitSource.contains("@ScaledMetric"))
        XCTAssertFalse(appKitSource.contains("@ScaledMetric"))
        XCTAssertTrue(uiKitSource.contains("AppFontStyle.scaledMetric("))
        XCTAssertTrue(appKitSource.contains("AppFontStyle.scaledMetric("))
    }

    func testUIKitAccessoryButtonsAreVerticallyCenteredInComposer() throws {
        let uiKitSource = try chatInputSource(named: "ChatInputUIKit.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            uiKitSource.contains("attachButton.centerYAnchor.constraint(equalTo:containerView.centerYAnchor)")
        )
        XCTAssertTrue(
            uiKitSource.contains("button.centerYAnchor.constraint(equalTo:containerView.centerYAnchor)")
        )
        XCTAssertFalse(
            uiKitSource.contains("attachButton.bottomAnchor.constraint(equalTo:containerView.bottomAnchor")
        )
        XCTAssertFalse(
            uiKitSource.contains("button.bottomAnchor.constraint(equalTo:containerView.bottomAnchor")
        )
    }

    func testUIKitComposerEnablesSelectableTextInteraction() throws {
        let uiKitSource = try chatInputSource(named: "ChatInputUIKit.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(uiKitSource.contains("textView.isSelectable=true"))
    }

    func testUIKitComposerExposesStableMessageFieldIdentifier() throws {
        let uiKitSource = try chatInputSource(named: "ChatInputUIKit.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(uiKitSource.contains("textView.accessibilityIdentifier=\"chat-message-text-view\""))
    }

    func testUIKitComposerRequestsFirstResponderWhenTappedWithoutFocus() throws {
        let uiKitSource = try chatInputSource(named: "ChatInputUIKit.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(uiKitSource.contains("overridefunctouchesEnded(_touches:Set<UITouch>,withevent:UIEvent?){"))
        XCTAssertTrue(uiKitSource.contains("guardisEditable,isUserInteractionEnabled,!isFirstResponderelse{return}"))
        XCTAssertTrue(uiKitSource.contains("letdidBecomeFirstResponder=becomeFirstResponder()"))
        XCTAssertTrue(uiKitSource.contains("recordFocusAttempt(source:\"touchesEnded\",succeeded:didBecomeFirstResponder)"))
    }

    func testUIKitComposerPublishesUITestDiagnosticsInAccessibilityValue() throws {
        let uiKitSource = try chatInputSource(named: "ChatInputUIKit.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(uiKitSource.contains("privatestaticletuiTestDiagnosticsEnvironmentKey=\"SIDEBAR_UI_TEST_USE_IN_MEMORY_AUTH\""))
        XCTAssertTrue(uiKitSource.contains("funcrefreshUITestAccessibilityValue(){"))
        XCTAssertTrue(uiKitSource.contains("accessibilityValue=["))
        XCTAssertTrue(uiKitSource.contains("\"editable=\\(isEditable?1:0)\""))
        XCTAssertTrue(uiKitSource.contains("\"lastFocusAttemptSource=\\(lastFocusAttemptSource)\""))
        XCTAssertTrue(uiKitSource.contains("letlastFocusAttemptSucceededValue:String"))
        XCTAssertTrue(uiKitSource.contains("\"lastFocusAttemptSucceeded=\\(lastFocusAttemptSucceededValue)\""))
    }

    func testUIKitComposerRecordsAutofocusAndTapFocusAttemptsForUITestDiagnostics() throws {
        let uiKitSource = try chatInputSource(named: "ChatInputUIKit.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(uiKitSource.contains("funcrecordFocusAttempt(source:String,succeeded:Bool){"))
        XCTAssertTrue(uiKitSource.contains("textView.recordFocusAttempt(source:\"autofocus\",succeeded:didBecomeFirstResponder)"))
        XCTAssertTrue(uiKitSource.contains("recordFocusAttempt(source:\"touchesEnded\",succeeded:didBecomeFirstResponder)"))
    }

    func testUIKitComposerSyncsFocusBeforeCollapsedStateEarlyReturn() throws {
        let uiKitSource = try chatInputSource(named: "ChatInputUIKit.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            uiKitSource.contains(
                "ifcontext.coordinator.syncCollapsedStateIfNeeded(for:textView,text:text){"
                    + "context.coordinator.syncFocusIfNeeded(for:textView,isEnabled:isEnabled,isFocused:isFocused)"
            )
        )
    }

    func testUIKitComposerReschedulesAutofocusAfterWindowAttachment() throws {
        let uiKitSource = try chatInputSource(named: "ChatInputUIKit.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(uiKitSource.contains("textView.onDidMoveToWindow=context.coordinator.handleTextViewDidMoveToWindow"))
        let didMoveToWindowHandler =
            "funchandleTextViewDidMoveToWindow(_textView:ChatInputTextView){" +
            "textView.refreshUITestAccessibilityValue()" +
            "scheduleAutofocusIfNeeded(for:textView)}"
        XCTAssertTrue(uiKitSource.contains(didMoveToWindowHandler))
        XCTAssertTrue(uiKitSource.contains("chatTextView.shouldAutofocus=isEnabled&&isFocused"))
        XCTAssertTrue(uiKitSource.contains("guard!textView.hasScheduledAutofocuselse{return}"))
        XCTAssertTrue(uiKitSource.contains("letdidBecomeFirstResponder=textView.becomeFirstResponder()"))
        XCTAssertTrue(uiKitSource.contains("textView.recordFocusAttempt(source:\"autofocus\",succeeded:didBecomeFirstResponder)"))
    }

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

    func testTextViewDisablesEvenWhenFocusedIfInputIsDisabled() {
        XCTAssertFalse(
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

    func testDeferredHeightStateCancelsStalePendingTargetWhenCurrentStateAlreadyMatchesNewTarget() {
        var state = ChatInputDeferredHeightState()

        XCTAssertTrue(state.shouldSchedule(currentMeasuredHeight: 0, targetMeasuredHeight: 96))
        XCTAssertFalse(state.shouldSchedule(currentMeasuredHeight: 0, targetMeasuredHeight: 0))
        XCTAssertNil(state.pendingMeasuredHeight)
        XCTAssertFalse(state.shouldApplyScheduled(measuredHeight: 96))
    }
}

private func chatInputSource(
    named fileName: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sourceURL = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("sideBar")
        .appendingPathComponent("Views")
        .appendingPathComponent("Chat")
        .appendingPathComponent(fileName)

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read \(fileName): \(error)", file: file, line: line)
        throw error
    }
}
