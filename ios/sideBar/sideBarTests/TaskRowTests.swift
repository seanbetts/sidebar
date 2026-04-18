import SwiftUI
import XCTest
@testable import sideBar

final class TaskRowTests: XCTestCase {
    func testTaskRowTapGestureIgnoresSubviewInteractions() {
        XCTAssertEqual(taskRowTapGestureMask(), .gesture)
    }

    func testTaskRowCompletionActionIsReopenForCompletedSelection() {
        XCTAssertEqual(
            taskRowCompletionAction(selection: .completed, taskStatus: "completed"),
            .reopen
        )
    }
}
