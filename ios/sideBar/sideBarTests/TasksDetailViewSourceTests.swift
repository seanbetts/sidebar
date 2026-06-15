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
                "HeaderActionButton(icon:AppIcon.Action.add,accessibilityLabel:\"Newtask\""
            )
        )
        let compactPlusIcon =
            "Image(systemName:\"plus\").appFont(.subheading)." +
            "foregroundStyle(DesignTokens.Colors.textSecondary).frame(width:28,height:28)"
        XCTAssertFalse(
            normalized.contains(compactPlusIcon)
        )
    }

    func testUpcomingEmptySectionPlaceholderUsesRegularBodyTypography() throws {
        let normalized = try tasksDetailViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        guard let placeholderRange = normalized.range(of: "Label(\"Notasksdue\"") else {
            XCTFail("Expected TasksDetailView to render the upcoming empty section placeholder.")
            return
        }
        let placeholderSource = normalized[placeholderRange.lowerBound...]
            .prefix(while: { $0 != "}" })

        XCTAssertTrue(placeholderSource.contains(".appFont(.body)"))
        XCTAssertFalse(placeholderSource.contains(".appFont(.subheading)"))
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
