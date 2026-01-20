import XCTest
@testable import sideBar

final class FileNameFormattingTests: XCTestCase {
    func testStripFileExtensionRemovesExtension() {
        XCTAssertEqual(stripFileExtension("note.md"), "note")
    }

    func testStripFileExtensionKeepsNameWithoutExtension() {
        XCTAssertEqual(stripFileExtension("README"), "README")
    }

    func testStripFileExtensionHandlesWhitespace() {
        XCTAssertEqual(stripFileExtension("  report.pdf "), "report")
    }
}
