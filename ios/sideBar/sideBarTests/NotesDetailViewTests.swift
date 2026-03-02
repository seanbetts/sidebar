import XCTest
@testable import sideBar

final class NotesDetailViewTests: XCTestCase {
    func testNotesDetailViewTypeLoads() {
        XCTAssertNotNil(NotesDetailView.self)
    }
}
