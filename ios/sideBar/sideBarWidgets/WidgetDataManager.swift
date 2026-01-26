import Foundation
import WidgetKit

/// Manages shared data between the main app and widgets via App Group UserDefaults.
/// Note: This is a copy of the main app's WidgetDataManager for the widget extension target.
public final class WidgetDataManager {
    public static let shared = WidgetDataManager()

    private let todayTasksKey = "widgetTodayTasks"
    private let isAuthenticatedKey = "widgetIsAuthenticated"
    private let pendingCompletionsKey = "widgetPendingCompletions"

    private init() {}

    // MARK: - App Group Access

    private var userDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    private var appGroupId: String {
        // Hardcoded to ensure consistency between main app and widget
        "group.ai.sidebar.sidebar"
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
        guard let defaults = userDefaults else {
            return false
        }
        return defaults.bool(forKey: isAuthenticatedKey)
    }

    /// Debug: returns description of what's in UserDefaults
    public func debugInfo() -> String {
        guard let defaults = userDefaults else {
            return "No defaults for: \(appGroupId)"
        }

        // Self-test: write and read back
        let testKey = "widgetSelfTest"
        defaults.set(true, forKey: testKey)
        defaults.synchronize()
        let selfTest = defaults.bool(forKey: testKey)

        let auth = defaults.bool(forKey: isAuthenticatedKey)
        // Try reading from shared file
        let fileAuth = readFromSharedFile()

        let containerName = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)?.lastPathComponent ?? "?"
        return "f=\(fileAuth) c=\(containerName.prefix(8))"
    }

    private func readFromSharedFile() -> String {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            return "NC" // no container
        }
        let fileURL = containerURL.appendingPathComponent("widget_auth.txt")
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return "NF" // no file
        }
        return content // should be "true" or "false"
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
}
