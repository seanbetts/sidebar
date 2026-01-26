import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

// MARK: - Widget Task Models

/// Lightweight task model for widgets (subset of TaskItem)
public struct WidgetTask: Codable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let isCompleted: Bool
    public let projectName: String?
    public let hasNotes: Bool

    public init(
        id: String,
        title: String,
        isCompleted: Bool = false,
        projectName: String? = nil,
        hasNotes: Bool = false
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.projectName = projectName
        self.hasNotes = hasNotes
    }
}

/// Data snapshot for widgets
public struct WidgetTaskData: Codable, Equatable {
    public let tasks: [WidgetTask]
    public let totalCount: Int
    public let lastUpdated: Date

    public init(tasks: [WidgetTask], totalCount: Int, lastUpdated: Date = Date()) {
        self.tasks = tasks
        self.totalCount = totalCount
        self.lastUpdated = lastUpdated
    }

    public static let empty = WidgetTaskData(tasks: [], totalCount: 0)

    public static let placeholder = WidgetTaskData(
        tasks: [
            WidgetTask(id: "1", title: "Review project proposal", projectName: "Work"),
            WidgetTask(id: "2", title: "Call dentist", hasNotes: true),
            WidgetTask(id: "3", title: "Buy groceries"),
            WidgetTask(id: "4", title: "Prepare presentation", projectName: "Work"),
        ],
        totalCount: 6
    )
}

// MARK: - Widget Data Manager

/// Manages shared data between the main app and widgets via App Group UserDefaults.
public final class WidgetDataManager {
    public static let shared = WidgetDataManager()

    private let todayTasksKey = "widgetTodayTasks"
    private let isAuthenticatedKey = "widgetIsAuthenticated"
    private let pendingCompletionsKey = "widgetPendingCompletions"

    private init() {}

    // MARK: - App Group Access

    private var userDefaults: UserDefaults? {
        guard let suiteName = appGroupId else { return nil }
        return UserDefaults(suiteName: suiteName)
    }

    private var appGroupId: String? {
        // Try configured value first
        if let configured = Bundle.main.object(forInfoDictionaryKey: "APP_GROUP_ID") as? String,
           !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !configured.contains("$(") {
            return configured
        }
        // Fall back to derived value
        guard let bundleId = Bundle.main.bundleIdentifier else { return nil }
        let normalized = bundleId
            .replacingOccurrences(of: ".ShareExtension", with: "")
            .replacingOccurrences(of: ".sideBarWidgets", with: "")
        return "group.\(normalized)"
    }

    // MARK: - Today Tasks

    /// Called by main app to update widget data
    public func updateTodayTasks(_ tasks: [WidgetTask], totalCount: Int) {
        let data = WidgetTaskData(tasks: tasks, totalCount: totalCount)
        guard let defaults = userDefaults else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let encoded = try? encoder.encode(data) {
            defaults.set(encoded, forKey: todayTasksKey)
            defaults.synchronize()
        }
        reloadWidgets()
    }

    /// Called by widgets to read cached data
    public func loadTodayTasks() -> WidgetTaskData {
        guard let defaults = userDefaults,
              let data = defaults.data(forKey: todayTasksKey) else {
            return .empty
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(WidgetTaskData.self, from: data)) ?? .empty
    }

    // MARK: - Authentication State

    /// Called by main app when auth state changes
    public func updateAuthState(isAuthenticated: Bool) {
        guard let defaults = userDefaults else { return }
        defaults.set(isAuthenticated, forKey: isAuthenticatedKey)
        defaults.synchronize()
        reloadWidgets()
    }

    /// Called by widgets to check auth state
    public func isAuthenticated() -> Bool {
        guard let defaults = userDefaults else { return false }
        return defaults.bool(forKey: isAuthenticatedKey)
    }

    // MARK: - Task Completion (Pending Operations)

    /// Records a task completion from widget (to be synced by main app)
    public func recordTaskCompletion(taskId: String) {
        guard let defaults = userDefaults else { return }
        var pending = loadPendingCompletions()
        if !pending.contains(taskId) {
            pending.append(taskId)
            if let encoded = try? JSONEncoder().encode(pending) {
                defaults.set(encoded, forKey: pendingCompletionsKey)
                defaults.synchronize()
            }
        }
    }

    /// Called by main app to get and clear pending completions
    public func consumePendingCompletions() -> [String] {
        guard let defaults = userDefaults else { return [] }
        let pending = loadPendingCompletions()
        defaults.removeObject(forKey: pendingCompletionsKey)
        defaults.synchronize()
        return pending
    }

    private func loadPendingCompletions() -> [String] {
        guard let defaults = userDefaults,
              let data = defaults.data(forKey: pendingCompletionsKey) else {
            return []
        }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    // MARK: - Widget Reload

    private func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

// MARK: - TaskItem to WidgetTask Conversion

extension WidgetTask {
    /// Creates a WidgetTask from a TaskItem with optional project name lookup
    public init(from task: TaskItem, projectName: String? = nil) {
        self.id = task.id
        self.title = task.title
        self.isCompleted = task.status == "completed"
        self.projectName = projectName
        self.hasNotes = task.notes != nil && !task.notes!.isEmpty
    }
}
