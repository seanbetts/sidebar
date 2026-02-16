import XCTest
@testable import sideBar

final class ChatMessageCopyFeedbackStateTests: XCTestCase {
    func testDefaultStateShowsCopyIconAndLabel() {
        let state = ChatMessageCopyFeedbackState()

        XCTAssertFalse(state.isCopied)
        XCTAssertEqual(state.iconName, "doc.on.doc")
        XCTAssertEqual(state.accessibilityLabel, "Copy message")
    }

    func testMarkCopiedSwitchesToSuccessState() {
        var state = ChatMessageCopyFeedbackState()

        state.markCopied()

        XCTAssertTrue(state.isCopied)
        XCTAssertEqual(state.iconName, "checkmark.circle.fill")
        XCTAssertEqual(state.accessibilityLabel, "Copied message")
    }

    func testResetReturnsToDefaultState() {
        var state = ChatMessageCopyFeedbackState()
        state.markCopied()

        state.reset()

        XCTAssertFalse(state.isCopied)
        XCTAssertEqual(state.iconName, "doc.on.doc")
        XCTAssertEqual(state.accessibilityLabel, "Copy message")
    }
}
