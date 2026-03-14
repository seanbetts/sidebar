import SwiftUI
import XCTest
@testable import sideBar

final class TaskRowTests: XCTestCase {
    func testTaskRowTapGestureIgnoresSubviewInteractions() {
        XCTAssertEqual(taskRowTapGestureMask(), .gesture)
    }
}
