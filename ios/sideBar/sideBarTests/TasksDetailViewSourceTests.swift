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
