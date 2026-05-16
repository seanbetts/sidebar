import XCTest

final class TasksPanelSourceTests: XCTestCase {
    func testTasksPanelGroupChooserUsesSharedActionConfirmationDialog() throws {
        let normalized = try tasksPanelSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains(".actionConfirmationDialog(title:\"Choosegroup\",isPresented:$showProjectGroupDialog)"))
        XCTAssertFalse(normalized.contains(".confirmationDialog(\"Choosegroup\""))
    }
}

private func tasksPanelSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sideBarRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = sideBarRoot
        .appendingPathComponent("sideBar")
        .appendingPathComponent("Views")
        .appendingPathComponent("SidebarPanels")
        .appendingPathComponent("TasksPanel.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read TasksPanel.swift: \(error)", file: file, line: line)
        throw error
    }
}
