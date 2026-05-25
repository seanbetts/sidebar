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

    func testTaskRowUsesIconTokenForCompletionControlSize() throws {
        let normalized = try taskRowSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains(".frame(width:DesignTokens.Icon.md,height:DesignTokens.Icon.md)"))
        XCTAssertFalse(normalized.contains(".frame(width:20,height:20)"))
    }

    func testTaskRowHasRowLevelAccessibilityLabel() throws {
        let normalized = try taskRowSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains(".accessibilityLabel(taskRowAccessibilityLabel("))
        XCTAssertEqual(
            taskRowAccessibilityLabel(
                task: TaskItem(
                    id: "task-1",
                    title: "Send proposal",
                    status: "completed",
                    notes: "Draft attached"
                ),
                dueLabel: "Today",
                repeatLabel: "Weekly",
                selection: .completed
            ),
            "Send proposal, completed, due Today, repeats Weekly, has notes"
        )
    }

    func testTaskRowIconActionsHaveAccessibilityLabels() throws {
        let normalized = try taskRowSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains(".accessibilityLabel(\"Deletecompletedtask\")"))
        XCTAssertTrue(normalized.contains(".accessibilityLabel(\"Taskactions\")"))
    }
}

private func taskRowSource(
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
        .appendingPathComponent("Tasks")
        .appendingPathComponent("TasksViewComponents.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read TasksViewComponents.swift: \(error)", file: file, line: line)
        throw error
    }
}
