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
        environment.authState = .active
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
        environment.authState = .active
        let operation = WidgetPendingOperation(itemId: "", action: NoteWidgetAction.addNew)
        WidgetDataManager.shared.recordPendingOperation(operation, for: .notes)

        environment.consumeWidgetAddNote()

        XCTAssertEqual(environment.commandSelection, .notes)
        XCTAssertTrue(environment.pendingNewNoteDeepLink)
    }

    func testRefreshAuthStateOnSignOutResetsNavigationViewModelsAndOfflineSnapshots() async {
        struct TestPayload: Codable, Equatable {
            let value: String
        }

        let environment = requireEnvironment()
        await environment.container.authSession.signOut()
        environment.authState = .active
        environment.pendingNewTaskDeepLink = true
        environment.pendingNewNoteDeepLink = true
        environment.pendingScratchpadDeepLink = true
        environment.tasksPhoneDetailRouteId = TaskSelection.today.cacheKey
        environment.tasksViewModel.updateSearch(query: "follow up")
        environment.tasksViewModel.startNewTask()
        environment.chatViewModel.selectedConversationId = "conversation-1"
        environment.chatViewModel.messages = [
            Message(
                id: "message-1",
                role: .assistant,
                content: "hi",
                status: .complete,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2026-01-01T00:00:00Z",
                error: nil
            )
        ]
        environment.offlineStore.set(
            key: "tests.signout.reset",
            entityType: "test",
            value: TestPayload(value: "value"),
            lastSyncAt: nil
        )

        environment.refreshAuthState()

        XCTAssertNil(environment.tasksViewModel.newTaskDraft)
        XCTAssertEqual(environment.tasksViewModel.searchQuery, "")
        XCTAssertNil(environment.tasksPhoneDetailRouteId)
        XCTAssertFalse(environment.pendingNewTaskDeepLink)
        XCTAssertFalse(environment.pendingNewNoteDeepLink)
        XCTAssertFalse(environment.pendingScratchpadDeepLink)
        XCTAssertNil(environment.chatViewModel.selectedConversationId)
        XCTAssertTrue(environment.chatViewModel.messages.isEmpty)
        let payload: TestPayload? = environment.offlineStore.get(
            key: "tests.signout.reset",
            as: TestPayload.self
        )
        XCTAssertNil(payload)
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
        environment.authState = .signedOut
        environment.commandSelection = nil
        environment.isTasksFocused = false
        environment.pendingNewTaskDeepLink = false
        environment.pendingNewNoteDeepLink = false
        environment.pendingScratchpadDeepLink = false
        environment.tasksPhoneDetailRouteId = nil
        environment.tasksViewModel.cancelNewTask()
        environment.tasksViewModel.reset()
        environment.chatViewModel.reset()
    }
}
