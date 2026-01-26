import Foundation
import WidgetKit

/// Manages shared data between the main app and widgets via App Group UserDefaults.
public final class WidgetDataManager {
    public static let shared = WidgetDataManager()

    private let todayTasksKey = "widgetTodayTasks"
    private let isAuthenticatedKey = "widgetIsAuthenticated"
    private let pendingCompletionsKey = "widgetPendingCompletions"
    private let pendingAddTaskKey = "widgetPendingAddTask"

    private init() {}

    // MARK: - App Group Access

    private var userDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    private var appGroupId: String {
        // Try configured value from Info.plist first
        if let configured = Bundle.main.object(forInfoDictionaryKey: "APP_GROUP_ID") as? String,
           !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !configured.contains("$(") {
            return configured
        }
        // Fall back to derived value from bundle ID
        let bundleId = Bundle.main.bundleIdentifier ?? "ai.sidebar.sidebar"
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
        WidgetCenter.shared.reloadTimelines(ofKind: "TodayTasksWidget")
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
        WidgetCenter.shared.reloadAllTimelines()
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

    // MARK: - Add Task Intent

    /// Records that the add task intent was triggered from widget
    public func recordAddTaskIntent() {
        guard let defaults = userDefaults else { return }
        defaults.set(true, forKey: pendingAddTaskKey)
        defaults.synchronize()
    }
}
