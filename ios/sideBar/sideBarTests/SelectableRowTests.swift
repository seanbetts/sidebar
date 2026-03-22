import SwiftUI
import XCTest
@testable import sideBar

final class SelectableRowTests: XCTestCase {
    func testSelectableRowWithoutPrimaryActionDoesNotWrapContentInButton() {
        let row = SelectableRow(isSelected: false) {
            Text("Row")
        }

        XCTAssertFalse(row.usesButtonBackedPrimaryAction)
    }

    func testSelectableRowWithPrimaryActionWrapsContentInButton() {
        let row = SelectableRow(
            isSelected: false,
            primaryAction: {},
            content: { Text("Row") }
        )

        XCTAssertTrue(row.usesButtonBackedPrimaryAction)
    }
}
