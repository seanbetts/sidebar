import Foundation
import WidgetKit

/// Lightweight widget data manager for extension use only.
/// Supports read operations and recording pending operations.
public final class WidgetDataManager {
  public static let shared = WidgetDataManager()

  private let authKey = "widgetIsAuthenticated"

  // Legacy keys (for backward compatibility during transition)
  private let legacyTodayTasksKey = "widgetTodayTasks"
  private let legacyPendingCompletionsKey = "widgetPendingCompletions"
  private let legacyPendingAddTaskKey = "widgetPendingAddTask"

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

  // MARK: - Generic Data Storage

  /// Loads widget data for a content type
  public func load<T: WidgetDataContainer>(for contentType: WidgetContentType) -> T {
    guard let defaults = userDefaults,
          let data = defaults.data(forKey: contentType.dataKey) else {
      return T.empty
    }
    return (try? Self.makeDecoder().decode(T.self, from: data)) ?? T.empty
  }

  /// Stores widget data for a content type (used for optimistic updates from intents)
  public func store<T: WidgetDataContainer>(_ data: T, for contentType: WidgetContentType) {
    guard let defaults = userDefaults else { return }
    if let encoded = try? Self.makeEncoder().encode(data) {
      defaults.set(encoded, forKey: contentType.dataKey)
      defaults.synchronize()
    }
    if let firstKind = contentType.widgetKinds.first {
      WidgetCenter.shared.reloadTimelines(ofKind: firstKind)
    }
  }

  // MARK: - Generic Pending Operations

  /// Records a pending operation from widget
  public func recordPendingOperation<A: Codable & Equatable>(
    _ operation: WidgetPendingOperation<A>,
    for contentType: WidgetContentType
  ) {
    guard let defaults = userDefaults else { return }
    var pending = loadPendingOperations(for: contentType, actionType: A.self)

    // Deduplicate by itemId + action
    if !pending.contains(where: { $0.itemId == operation.itemId && $0.action == operation.action }) {
      pending.append(operation)
      if let encoded = try? Self.makeEncoder().encode(pending) {
        defaults.set(encoded, forKey: contentType.pendingKey)
        defaults.synchronize()
      }
    }
  }

  private func loadPendingOperations<A: Codable & Equatable>(
    for contentType: WidgetContentType,
    actionType: A.Type
  ) -> [WidgetPendingOperation<A>] {
    guard let defaults = userDefaults,
          let data = defaults.data(forKey: contentType.pendingKey) else {
      return []
    }
    return (try? Self.makeDecoder().decode([WidgetPendingOperation<A>].self, from: data)) ?? []
  }

  // MARK: - Authentication State

  /// Called by widgets to check auth state
  public func isAuthenticated() -> Bool {
    userDefaults?.bool(forKey: authKey) ?? false
  }

  // MARK: - Encoder/Decoder

  private static func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }

  private static func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}

// MARK: - Backward Compatibility

extension WidgetDataManager {
  /// Backward compatible method for loading tasks
  public func loadTodayTasks() -> WidgetTaskData {
    // Try new key first, fall back to legacy key
    if let defaults = userDefaults,
       let data = defaults.data(forKey: WidgetContentType.tasks.dataKey) {
      if let decoded = try? Self.makeDecoder().decode(WidgetTaskData.self, from: data) {
        return decoded
      }
    }
    // Fall back to legacy key
    if let defaults = userDefaults,
       let data = defaults.data(forKey: legacyTodayTasksKey) {
      if let decoded = try? Self.makeDecoder().decode(WidgetTaskData.self, from: data) {
        return decoded
      }
    }
    return .empty
  }

  /// Backward compatible method for updating tasks (optimistic update from intent)
  public func updateTodayTasks(_ tasks: [WidgetTask], totalCount: Int) {
    let data = WidgetTaskData(tasks: tasks, totalCount: totalCount)
    store(data, for: .tasks)
  }

  /// Backward compatible method for recording task completion
  public func recordTaskCompletion(taskId: String) {
    let operation = WidgetPendingOperation(itemId: taskId, action: TaskWidgetAction.complete)
    recordPendingOperation(operation, for: .tasks)
  }

  /// Backward compatible method for recording add task intent
  public func recordAddTaskIntent() {
    let operation = WidgetPendingOperation(itemId: "", action: TaskWidgetAction.addNew)
    recordPendingOperation(operation, for: .tasks)
  }

  // MARK: - Quick Save

  private let pendingQuickSaveKey = "pendingQuickSaveURL"

  /// Records a URL to be saved when the app opens
  public func recordPendingQuickSave(url: URL) {
    guard let defaults = userDefaults else { return }
    defaults.set(url.absoluteString, forKey: pendingQuickSaveKey)
    defaults.synchronize()
  }

  /// Consumes the pending quick save URL (called by main app)
  public func consumePendingQuickSave() -> URL? {
    guard let defaults = userDefaults,
          let urlString = defaults.string(forKey: pendingQuickSaveKey),
          let url = URL(string: urlString) else {
      return nil
    }
    defaults.removeObject(forKey: pendingQuickSaveKey)
    defaults.synchronize()
    return url
  }
}
