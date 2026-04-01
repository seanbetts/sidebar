import AppIntents
import WidgetKit
import sideBarShared
import os
import Foundation

// MARK: - Complete Task Intent

/// Intent to mark a task as complete from a widget
struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Task"
    static var description = IntentDescription("Marks a task as complete")
    nonisolated(unsafe) static var syncTaskCompletion: @Sendable (WidgetPendingOperation<TaskWidgetAction>) async -> Bool = { operation in
        do {
            let environment = try WidgetAPIEnvironment()
            try await TaskWidgetCompletionSyncClient(environment: environment).completeTask(operation: operation)
            return true
        } catch {
            return false
        }
    }

    @Parameter(title: "Task ID")
    var taskId: String

    init() {}

    init(taskId: String) {
        self.taskId = taskId
    }

    func perform() async throws -> some IntentResult {
        guard UUID(uuidString: taskId) != nil else {
            return .result()
        }

        let operation = WidgetPendingOperation(itemId: taskId, action: TaskWidgetAction.complete)
        WidgetDataManager.shared.recordPendingOperation(operation, for: .tasks)
        WidgetTaskCompletionHandoffNotifier.post()

        // Update widget data optimistically (show checked state before disappearing)
        let data = WidgetDataManager.shared.loadTodayTasks()
        let wasAlreadyCompleted = data.tasks.first(where: { $0.id == taskId })?.isCompleted ?? false
        let completedAt = Date()
        let updatedTasks = data.tasks.map { task in
            guard task.id == taskId else { return task }
            return WidgetTask(
                id: task.id,
                title: task.title,
                isCompleted: true,
                completedAt: completedAt,
                projectName: task.projectName,
                groupName: task.groupName,
                hasNotes: task.hasNotes,
                deadline: task.deadline
            )
        }

        let baseProgressTotal = max(data.progressTotalCount, data.totalCount)
        let nextProgressCompletedCount: Int
        if wasAlreadyCompleted {
            nextProgressCompletedCount = min(data.progressCompletedCount, baseProgressTotal)
        } else {
            nextProgressCompletedCount = min(baseProgressTotal, data.progressCompletedCount + 1)
        }

        let nextTotalCount = wasAlreadyCompleted ? data.totalCount : max(0, data.totalCount - 1)
        WidgetDataManager.shared.updateTodayTasks(
            updatedTasks,
            totalCount: nextTotalCount,
            progressCompletedCount: nextProgressCompletedCount,
            progressTotalCount: baseProgressTotal
        )

        let didSync = await Self.syncTaskCompletion(operation)
        if didSync {
            WidgetDataManager.shared.removePendingOperation(
                withId: operation.id,
                for: .tasks,
                actionType: TaskWidgetAction.self
            )
            for kind in WidgetContentType.tasks.widgetKinds {
                WidgetCenter.shared.reloadTimelines(ofKind: kind)
            }
        }

        return .result()
    }
}

// MARK: - Open Today Intent

/// Intent to open the app to Today view
struct OpenTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Today"
    static var description = IntentDescription("Opens sideBar to Today's tasks")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & OpensIntent {
        guard let url = URL(string: "sidebar://tasks/today") else {
            return .result()
        }
        return .result(opensIntent: OpenURLIntent(url))
    }
}

// MARK: - Add Task Intent

/// Intent to open the app to add a new task
struct AddTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Task"
    static var description = IntentDescription("Opens sideBar to add a new task")
    static var openAppWhenRun: Bool = true
    private let logger = Logger(subsystem: "sideBar", category: "WidgetIntent")

    func perform() async throws -> some IntentResult & OpensIntent {
        logger.info("AddTaskIntent recording pending add task")
        WidgetDataManager.shared.recordAddTaskIntent()
        guard let url = URL(string: "sidebar://tasks/new") else {
            logger.error("AddTaskIntent failed: invalid deep link URL")
            return .result()
        }
        return .result(opensIntent: OpenURLIntent(url))
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

    func perform() async throws -> some IntentResult & OpensIntent {
        guard let url = URL(string: "sidebar://tasks/today") else {
            return .result()
        }
        return .result(opensIntent: OpenURLIntent(url))
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
        // Website shortcuts
        AppShortcut(
            intent: OpenWebsitesIntent(),
            phrases: [
                "Show my saved websites in \(.applicationName)",
                "Open websites in \(.applicationName)",
                "View my bookmarks in \(.applicationName)"
            ],
            shortTitle: "Saved Websites",
            systemImageName: "globe"
        )
        AppShortcut(
            intent: QuickSaveIntent(),
            phrases: [
                "Save this website in \(.applicationName)",
                "Bookmark this page in \(.applicationName)",
                "Save URL in \(.applicationName)"
            ],
            shortTitle: "Save Website",
            systemImageName: "bookmark.fill"
        )
        // File shortcuts
        AppShortcut(
            intent: OpenFilesIntent(),
            phrases: [
                "Show my files in \(.applicationName)",
                "Open files in \(.applicationName)",
                "View my documents in \(.applicationName)"
            ],
            shortTitle: "My Files",
            systemImageName: "doc"
        )
        // General shortcuts
        AppShortcut(
            intent: OpenScratchpadIntent(),
            phrases: [
                "Open scratchpad in \(.applicationName)",
                "Quick note in \(.applicationName)",
                "Scratch pad in \(.applicationName)"
            ],
            shortTitle: "Scratchpad",
            systemImageName: "note.text"
        )
        AppShortcut(
            intent: StartChatIntent(),
            phrases: [
                "Start a chat in \(.applicationName)",
                "New conversation in \(.applicationName)",
                "Chat with \(.applicationName)"
            ],
            shortTitle: "Start Chat",
            systemImageName: "bubble.left.and.bubble.right"
        )
    }
}
