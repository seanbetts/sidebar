import XCTest
@testable import sideBar

final class ChatInputKeyBehaviorTests: XCTestCase {
    func testReturnWithoutCommandInsertsNewline() {
        XCTAssertEqual(chatInputReturnIntent(commandPressed: false), .insertNewline)
    }

    func testReturnWithCommandSends() {
        XCTAssertEqual(chatInputReturnIntent(commandPressed: true), .send)
    }
}
