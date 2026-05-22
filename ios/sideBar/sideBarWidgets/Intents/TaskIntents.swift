import AppIntents
import WidgetKit
import sideBarShared
import os
import Foundation

// MARK: - Widget Configuration

enum TaskWidgetScope: String, AppEnum {
    case today
    case project
    case group

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Task Scope")
    static var caseDisplayRepresentations: [TaskWidgetScope: DisplayRepresentation] = [
        .today: DisplayRepresentation(title: "Today"),
        .project: DisplayRepresentation(title: "Project"),
        .group: DisplayRepresentation(title: "Group")
    ]
}

enum TaskWidgetSelection: Equatable, Sendable {
    case today
    case project(id: String, title: String)
    case group(id: String, title: String)

    var emptyStateContent: WidgetEmptyStateContent {
        switch self {
        case .today:
            return .allTasksCompleted(
                subtitle: "No tasks for today",
                appIcon: AppIcon.State.successCircle
            )
        case .project:
            return .allTasksCompleted(
                subtitle: "No open tasks in this project",
                appIcon: AppIcon.Tasks.project
            )
        case .group:
            return .allTasksCompleted(
                subtitle: "No open tasks in this group",
                appIcon: AppIcon.Widget.taskStack
            )
        }
    }

    var emptyStateTitle: String {
        emptyStateContent.title
    }
    var emptyStateSubtitle: String {
        emptyStateContent.subtitle ?? ""
    }
    var emptyStateSystemImage: String {
        emptyStateAppIcon.rawValue
    }
    var emptyStateAppIcon: AppIcon {
        emptyStateContent.appIcon
    }
    var lockScreenEmptyLabel: String {
        emptyStateContent.lockScreenLabel
    }
    var cacheKey: String {
        switch self {
        case .today:
            return "today"
        case .project(let id, let title):
            return "project:\(id):\(Self.encodeTitle(title))"
        case .group(let id, let title):
            return "group:\(id):\(Self.encodeTitle(title))"
        }
    }
    var headerTitle: String {
        switch self {
        case .today:
            return "Tasks"
        case .project(_, let title), .group(_, let title):
            return title
        }
    }
    var standByTitle: String {
        switch self {
        case .today:
            return "Today"
        case .project(_, let title), .group(_, let title):
            return title
        }
    }

    var deepLinkURL: URL {
        let path: String
        switch self {
        case .today:
            path = "sidebar://tasks/today"
        case .project(let id, _):
            path = "sidebar://tasks/project/\(id)"
        case .group(let id, _):
            path = "sidebar://tasks/group/\(id)"
        }
        return URL(string: path) ?? URL(string: "sidebar://tasks/today")!
    }

    static func from(cacheKey: String?) -> TaskWidgetSelection {
        guard let cacheKey, !cacheKey.isEmpty else { return .today }
        if cacheKey == "today" {
            return .today
        }

        let components = cacheKey.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard components.count >= 2 else {
            return .today
        }

        let id = String(components[1])
        let title = components.count == 3 ? decodeTitle(String(components[2])) : id
        switch String(components[0]) {
        case "project":
            return .project(id: id, title: title)
        case "group":
            return .group(id: id, title: title)
        default:
            return .today
        }
    }

    private static func encodeTitle(_ title: String) -> String {
        title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
    }

    private static func decodeTitle(_ encodedTitle: String) -> String {
        encodedTitle.removingPercentEncoding ?? encodedTitle
    }
}

struct TaskProjectEntity: AppEntity, Identifiable, Hashable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Task Project")
    static var defaultQuery = TaskProjectEntityQuery()

    let id: String
    let title: String
    let groupId: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

struct TaskGroupEntity: AppEntity, Identifiable, Hashable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Task Group")
    static var defaultQuery = TaskGroupEntityQuery()

    let id: String
    let title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

struct TaskProjectEntityQuery: EntityQuery {
    func entities(for identifiers: [TaskProjectEntity.ID]) async throws -> [TaskProjectEntity] {
        let projects = WidgetDataManager.shared.loadTaskConfigurationCatalog().projects.map {
            TaskProjectEntity(id: $0.id, title: $0.title, groupId: $0.groupId)
        }
        let projectsById = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        return identifiers.compactMap { id in
            projectsById[id] ?? TaskProjectEntity(id: id, title: id, groupId: nil)
        }
    }

    func suggestedEntities() async throws -> [TaskProjectEntity] {
        WidgetDataManager.shared.loadTaskConfigurationCatalog().projects.map {
            TaskProjectEntity(id: $0.id, title: $0.title, groupId: $0.groupId)
        }
    }
}

struct TaskGroupEntityQuery: EntityQuery {
    func entities(for identifiers: [TaskGroupEntity.ID]) async throws -> [TaskGroupEntity] {
        let groups = WidgetDataManager.shared.loadTaskConfigurationCatalog().groups.map {
            TaskGroupEntity(id: $0.id, title: $0.title)
        }
        let groupsById = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
        return identifiers.compactMap { id in
            groupsById[id] ?? TaskGroupEntity(id: id, title: id)
        }
    }

    func suggestedEntities() async throws -> [TaskGroupEntity] {
        WidgetDataManager.shared.loadTaskConfigurationCatalog().groups.map {
            TaskGroupEntity(id: $0.id, title: $0.title)
        }
    }
}

struct TaskWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Task Widget"
    static var description = IntentDescription("Choose which task list the widget should show.")

    @Parameter(title: "Scope", default: .today)
    var scope: TaskWidgetScope

    @Parameter(title: "Project")
    var project: TaskProjectEntity?

    @Parameter(title: "Group")
    var group: TaskGroupEntity?

    init() {
        scope = .today
    }

    init(selection: TaskWidgetSelection) {
        switch selection {
        case .today:
            scope = .today
        case .project(let id, let title):
            scope = .project
            project = TaskProjectEntity(id: id, title: title, groupId: nil)
        case .group(let id, let title):
            scope = .group
            group = TaskGroupEntity(id: id, title: title)
        }
    }

    static var parameterSummary: some ParameterSummary {
        Switch(\.$scope) {
            Case(.project) {
                Summary("Show \(\.$scope) tasks") {
                    \.$project
                }
            }
            Case(.group) {
                Summary("Show \(\.$scope) tasks") {
                    \.$group
                }
            }
            DefaultCase {
                Summary("Show \(\.$scope) tasks")
            }
        }
    }

    var selection: TaskWidgetSelection {
        switch scope {
        case .today:
            return .today
        case .project:
            if let project {
                return .project(id: project.id, title: project.title)
            }
            return .today
        case .group:
            if let group {
                return .group(id: group.id, title: group.title)
            }
            return .today
        }
    }
}
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
    @Parameter(title: "Selection")
    var selectionKey: String?

    init() {}

    init(taskId: String, selectionKey: String? = nil) {
        self.taskId = taskId
        self.selectionKey = selectionKey
    }

    func perform() async throws -> some IntentResult {
        guard UUID(uuidString: taskId) != nil else {
            return .result()
        }

        let selection = TaskWidgetSelection.from(cacheKey: selectionKey)
        let operation = WidgetPendingOperation(itemId: taskId, action: TaskWidgetAction.complete)
        WidgetDataManager.shared.recordPendingOperation(operation, for: .tasks)
        WidgetTaskCompletionHandoffNotifier.post()

        // Update widget data optimistically (show checked state before disappearing)
        let data = WidgetDataManager.shared.loadTaskData(for: selection)
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
        WidgetDataManager.shared.updateTaskData(
            updatedTasks,
            for: selection,
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
        guard let url = URL(string: "sidebar://tasks/new") else {
            logger.error("AddTaskIntent failed: invalid deep link URL")
            return .result()
        }
        logger.info("AddTaskIntent opening deep link")
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
