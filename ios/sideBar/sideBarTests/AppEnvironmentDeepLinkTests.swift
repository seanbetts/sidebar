import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class AppEnvironmentDeepLinkTests: XCTestCase {
    override func setUp() {
        super.setUp()
        clearWidgetPendingOperations()
        let environment = requireEnvironment()
        resetDeepLinkState(environment)
    }

    override func tearDown() {
        let environment = requireEnvironment()
        resetDeepLinkState(environment)
        clearWidgetPendingOperations()
        super.tearDown()
    }

    func testHandleNotesNewDeepLinkSetsPendingFlagAndSelection() {
        let environment = requireEnvironment()

        environment.handleDeepLink(URL(string: "sidebar://notes/new")!)

        XCTAssertEqual(environment.commandSelection, .notes)
        XCTAssertTrue(environment.pendingNewNoteDeepLink)
    }

    func testHandleTasksNewDeepLinkWhenNotFocusedSetsPendingFlag() {
        let environment = requireEnvironment()

        environment.handleDeepLink(URL(string: "sidebar://tasks/new")!)

        XCTAssertEqual(environment.commandSelection, .tasks)
        XCTAssertTrue(environment.pendingNewTaskDeepLink)
        XCTAssertNil(environment.tasksViewModel.newTaskDraft)
    }

    func testHandleTasksNewDeepLinkWhenFocusedStartsNewTaskImmediately() {
        let environment = requireEnvironment()
        environment.isTasksFocused = true

        environment.handleDeepLink(URL(string: "sidebar://tasks/new")!)

        XCTAssertEqual(environment.commandSelection, .tasks)
        XCTAssertFalse(environment.pendingNewTaskDeepLink)
        XCTAssertNotNil(environment.tasksViewModel.newTaskDraft)
    }

    func testConsumeWidgetAddTaskStartsTaskImmediatelyWhenTasksFocused() {
        let environment = requireEnvironment()
        environment.isAuthenticated = true
        environment.isTasksFocused = true

        let operation = WidgetPendingOperation(itemId: "", action: TaskWidgetAction.addNew)
        WidgetDataManager.shared.recordPendingOperation(operation, for: .tasks)

        environment.consumeWidgetAddTask()

        XCTAssertEqual(environment.commandSelection, .tasks)
        XCTAssertFalse(environment.pendingNewTaskDeepLink)
        XCTAssertNotNil(environment.tasksViewModel.newTaskDraft)
    }

    func testConsumeWidgetAddNoteSetsPendingFlagAndSelection() {
        let environment = requireEnvironment()
        environment.isAuthenticated = true
        let operation = WidgetPendingOperation(itemId: "", action: NoteWidgetAction.addNew)
        WidgetDataManager.shared.recordPendingOperation(operation, for: .notes)

        environment.consumeWidgetAddNote()

        XCTAssertEqual(environment.commandSelection, .notes)
        XCTAssertTrue(environment.pendingNewNoteDeepLink)
    }

    private func clearWidgetPendingOperations() {
        _ = WidgetDataManager.shared.consumePendingOperations(for: .tasks, actionType: TaskWidgetAction.self)
        _ = WidgetDataManager.shared.consumePendingOperations(for: .notes, actionType: NoteWidgetAction.self)
    }

    private func requireEnvironment(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> AppEnvironment {
        for _ in 0..<20 {
            if let environment = AppEnvironment.shared {
                return environment
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        XCTFail("Expected shared app environment", file: file, line: line)
        return AppEnvironment.shared!
    }

    private func resetDeepLinkState(_ environment: AppEnvironment) {
        environment.commandSelection = nil
        environment.isTasksFocused = false
        environment.pendingNewTaskDeepLink = false
        environment.pendingNewNoteDeepLink = false
        environment.tasksViewModel.cancelNewTask()
    }
}
