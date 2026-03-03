import XCTest
@testable import sideBar

@MainActor
final class ChatInputKeyBehaviorTests: XCTestCase {
    func testReturnWithoutShiftSends() {
        XCTAssertEqual(chatInputReturnIntent(shiftPressed: false), .send)
    }

    func testReturnWithShiftInsertsNewline() {
        XCTAssertEqual(chatInputReturnIntent(shiftPressed: true), .insertNewline)
    }
}
