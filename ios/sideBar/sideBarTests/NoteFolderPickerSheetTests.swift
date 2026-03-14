import XCTest
@testable import sideBar

final class NoteFolderPickerSheetTests: XCTestCase {
    func testFolderOptionBuildIncludesRootFirst() {
        let options = FolderOption.build(from: [])

        XCTAssertEqual(options.first?.label, "Notes")
        XCTAssertEqual(options.first?.value, "")
    }
}
