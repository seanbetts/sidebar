import XCTest
@testable import sideBar

final class RenameTaskSheetTests: XCTestCase {
    func testCanSaveRenamedTaskTitleReturnsFalseWhenEditedTitleIsEmpty() {
        XCTAssertFalse(canSaveRenamedTaskTitle(originalTitle: "Current title", editedTitle: "   "))
    }

    func testCanSaveRenamedTaskTitleReturnsFalseWhenEditedTitleMatchesOriginal() {
        XCTAssertFalse(canSaveRenamedTaskTitle(originalTitle: "Current title", editedTitle: "Current title"))
    }

    func testCanSaveRenamedTaskTitleReturnsTrueWhenEditedTitleChanges() {
        XCTAssertTrue(canSaveRenamedTaskTitle(originalTitle: "Current title", editedTitle: "Updated title"))
    }
}
