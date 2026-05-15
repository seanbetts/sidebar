import XCTest
import sideBarShared
@testable import sideBar

final class ChatMessageCopyFeedbackStateTests: XCTestCase {
    func testDefaultStateShowsCopyIconAndLabel() {
        let state = ChatMessageCopyFeedbackState()

        XCTAssertFalse(state.isCopied)
        XCTAssertEqual(state.appIcon, AppIcon.Action.copy)
        XCTAssertEqual(state.accessibilityLabel, "Copy message")
        XCTAssertEqual(state.foregroundStyle, .secondary)
        XCTAssertFalse(state.usesContrastingBackground)
    }

    func testMarkCopiedSwitchesToSuccessState() {
        var state = ChatMessageCopyFeedbackState()

        state.markCopied()

        XCTAssertTrue(state.isCopied)
        XCTAssertEqual(state.appIcon, AppIcon.State.successCircle)
        XCTAssertEqual(state.accessibilityLabel, "Copied message")
        XCTAssertEqual(state.foregroundStyle, .primary)
        XCTAssertFalse(state.usesContrastingBackground)
    }

    func testResetReturnsToDefaultState() {
        var state = ChatMessageCopyFeedbackState()
        state.markCopied()

        state.reset()

        XCTAssertFalse(state.isCopied)
        XCTAssertEqual(state.appIcon, AppIcon.Action.copy)
        XCTAssertEqual(state.accessibilityLabel, "Copy message")
    }
}
