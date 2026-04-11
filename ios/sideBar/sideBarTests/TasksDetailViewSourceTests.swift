import XCTest

final class TasksDetailViewSourceTests: XCTestCase {
    func testTasksDetailHeaderUsesSharedFixedContentHeaderHeight() throws {
        let normalized = try tasksDetailViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            normalized.contains(
                "privatefuncheader(state:TasksViewState)->someView{" +
                    "ContentHeaderRow("
            )
        )
        XCTAssertTrue(
            normalized.contains(
                ".frame(height:LayoutMetrics.contentHeaderMinHeight,alignment:.leading)"
            )
        )
    }

    func testCompactTasksHeaderUsesSharedHeaderActionButtonForNewTask() throws {
        let normalized = try tasksDetailViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            normalized.contains(
                "privatefunccompactHeader(state:TasksViewState)->someView{"
            )
        )
        XCTAssertTrue(
            normalized.contains(
                "HeaderActionButton(systemName:\"plus\",accessibilityLabel:\"Newtask\""
            )
        )
        let compactPlusIcon =
            "Image(systemName:\"plus\").appFont(.subheadline)." +
            "foregroundStyle(DesignTokens.Colors.textSecondary).frame(width:28,height:28)"
        XCTAssertFalse(
            normalized.contains(compactPlusIcon)
        )
    }

    private func tasksDetailViewSource(file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let sideBarRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sideBarRoot
            .appendingPathComponent("sideBar")
            .appendingPathComponent("Views")
            .appendingPathComponent("Tasks")
            .appendingPathComponent("TasksDetailView.swift")

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read tasks detail view source: \(error)", file: file, line: line)
            throw error
        }
    }
}
