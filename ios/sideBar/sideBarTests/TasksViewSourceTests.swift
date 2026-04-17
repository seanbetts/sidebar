import XCTest

final class TasksViewSourceTests: XCTestCase {
    func testTasksViewDoesNotOwnScenePhaseRefresh() throws {
        let normalized = try tasksViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(normalized.contains("@Environment(\\.scenePhase)"))
        XCTAssertFalse(normalized.contains("scenePhase==.active"))
        XCTAssertFalse(normalized.contains(".onChange(of:scenePhase)"))
        XCTAssertFalse(normalized.contains(".task{awaitenvironment.tasksViewModel.load("))
        XCTAssertTrue(normalized.contains("guardenvironment.pendingNewTaskDeepLinkelse{return}"))
        XCTAssertTrue(normalized.contains("awaitenvironment.tasksViewModel.load(selection:.today)"))
        XCTAssertTrue(normalized.contains("environment.tasksViewModel.startNewTask()"))
    }

    private func tasksViewSource(
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
            .appendingPathComponent("TasksView.swift")

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read TasksView.swift: \(error)", file: file, line: line)
            throw error
        }
    }
}
