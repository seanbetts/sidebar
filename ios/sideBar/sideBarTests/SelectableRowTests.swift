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

    func testSelectableRowSourceUsesSharedHoverModifierForBackgroundState() throws {
        let normalized = try selectableRowSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("@StateprivatevarisHovered=false"))
        XCTAssertTrue(normalized.contains(".sidebarHover($isHovered)"))
        XCTAssertTrue(normalized.contains("isHovered&&!isSelected"))
    }
}

private func selectableRowSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sideBarRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = sideBarRoot
        .appendingPathComponent("sideBar")
        .appendingPathComponent("Design")
        .appendingPathComponent("Components")
        .appendingPathComponent("SelectableRow.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read SelectableRow.swift: \(error)", file: file, line: line)
        throw error
    }
}
