import XCTest
@testable import sideBar

final class TasksNotesKeyBehaviorTests: XCTestCase {
    func testReturnWithoutCommandInsertsNewline() {
        XCTAssertEqual(notesEditorReturnIntent(commandPressed: false), .insertNewline)
    }

    func testReturnWithCommandSubmits() {
        XCTAssertEqual(notesEditorReturnIntent(commandPressed: true), .submit)
    }
}
