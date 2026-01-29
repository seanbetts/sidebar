import AppIntents
import WidgetKit
import os

// MARK: - Complete Task Intent

/// Intent to mark a task as complete from a widget
struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Task"
    static var description = IntentDescription("Marks a task as complete")

    @Parameter(title: "Task ID")
    var taskId: String

    init() {}

    init(taskId: String) {
        self.taskId = taskId
    }

    func perform() async throws -> some IntentResult {
        // Record the completion for the main app to sync
        WidgetDataManager.shared.recordTaskCompletion(taskId: taskId)

        // Update widget data optimistically (remove the completed task)
        let data = WidgetDataManager.shared.loadTodayTasks()
        let updatedTasks = data.tasks.filter { $0.id != taskId }
        WidgetDataManager.shared.updateTodayTasks(updatedTasks, totalCount: max(0, data.totalCount - 1))

        return .result()
    }
}

// MARK: - Open Today Intent

/// Intent to open the app to Today view
struct OpenTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Today"
    static var description = IntentDescription("Opens sideBar to Today's tasks")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        // The app will handle the deep link via URL scheme
        return .result()
    }
}

// MARK: - Add Task Intent

/// Intent to open the app to add a new task
struct AddTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Task"
    static var description = IntentDescription("Opens sideBar to add a new task")
    static var openAppWhenRun: Bool = true
    private let logger = Logger(subsystem: "sideBar", category: "WidgetIntent")

    func perform() async throws -> some IntentResult {
        logger.info("AddTaskIntent recording pending add task")
        WidgetDataManager.shared.recordAddTaskIntent()
        return .result()
    }
}

// MARK: - Open Task Intent

/// Intent to open a specific task in the app
struct OpenTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Task"
    static var description = IntentDescription("Opens a specific task in sideBar")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Task ID")
    var taskId: String

    init() {}

    init(taskId: String) {
        self.taskId = taskId
    }

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

// MARK: - App Shortcuts Provider

struct SideBarShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // Task shortcuts
        AppShortcut(
            intent: OpenTodayIntent(),
            phrases: [
                "Show my tasks in \(.applicationName)",
                "Open today's tasks in \(.applicationName)",
                "What do I have to do today in \(.applicationName)"
            ],
            shortTitle: "Today's Tasks",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Add a task in \(.applicationName)",
                "Create a new task in \(.applicationName)",
                "New task in \(.applicationName)"
            ],
            shortTitle: "Add Task",
            systemImageName: "plus.circle"
        )
        // Note shortcuts
        AppShortcut(
            intent: OpenNotesIntent(),
            phrases: [
                "Show my notes in \(.applicationName)",
                "Open notes in \(.applicationName)",
                "View my notes in \(.applicationName)"
            ],
            shortTitle: "My Notes",
            systemImageName: "doc.text"
        )
        AppShortcut(
            intent: CreateNoteIntent(),
            phrases: [
                "Create a note in \(.applicationName)",
                "New note in \(.applicationName)",
                "Add a note in \(.applicationName)"
            ],
            shortTitle: "Create Note",
            systemImageName: "doc.badge.plus"
        )
    }
}
