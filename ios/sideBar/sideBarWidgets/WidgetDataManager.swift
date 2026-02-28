import Foundation
import WidgetKit

/// Lightweight widget data manager for extension use only.
/// Supports read operations and recording pending operations.
public final class WidgetDataManager {
  public static let shared = WidgetDataManager()

  private let authKey = "widgetIsAuthenticated"
  private let faviconR2EndpointKey = "widget_favicon_r2_endpoint"
  private let faviconR2BucketKey = "widget_favicon_r2_bucket"
  private let faviconR2PublicBaseUrlKey = "widget_favicon_r2_public_base_url"

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
    for kind in contentType.widgetKinds {
      WidgetCenter.shared.reloadTimelines(ofKind: kind)
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

  public func faviconConfiguration() -> WidgetFaviconConfigurationValues {
    let endpoint = optionalHTTPURL(forUserDefaultsKey: faviconR2EndpointKey)
    let bucket = optionalString(forUserDefaultsKey: faviconR2BucketKey)
    let publicBaseURL = optionalHTTPURL(forUserDefaultsKey: faviconR2PublicBaseUrlKey)
    return WidgetFaviconConfigurationValues(
      r2Endpoint: endpoint,
      r2FaviconBucket: bucket,
      r2FaviconPublicBaseUrl: publicBaseURL
    )
  }

  // MARK: - Encoder/Decoder

  private func optionalString(forUserDefaultsKey key: String) -> String? {
    guard let raw = userDefaults?.string(forKey: key) else {
      return nil
    }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.contains("$(") else {
      return nil
    }
    return trimmed
  }

  private func optionalHTTPURL(forUserDefaultsKey key: String) -> URL? {
    guard let raw = optionalString(forUserDefaultsKey: key),
          let parsed = URL(string: raw),
          let scheme = parsed.scheme?.lowercased(),
          ["http", "https"].contains(scheme) else {
      return nil
    }
    return parsed
  }

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

public struct WidgetFaviconConfigurationValues {
  public let r2Endpoint: URL?
  public let r2FaviconBucket: String?
  public let r2FaviconPublicBaseUrl: URL?

  public init(
    r2Endpoint: URL?,
    r2FaviconBucket: String?,
    r2FaviconPublicBaseUrl: URL?
  ) {
    self.r2Endpoint = r2Endpoint
    self.r2FaviconBucket = r2FaviconBucket
    self.r2FaviconPublicBaseUrl = r2FaviconPublicBaseUrl
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
  public func updateTodayTasks(
    _ tasks: [WidgetTask],
    totalCount: Int,
    progressCompletedCount: Int? = nil,
    progressTotalCount: Int? = nil
  ) {
    let existing = loadTodayTasks()
    let data = WidgetTaskData(
      tasks: tasks,
      totalCount: totalCount,
      progressCompletedCount: progressCompletedCount ?? existing.progressCompletedCount,
      progressTotalCount: progressTotalCount ?? max(totalCount, existing.progressTotalCount)
    )
    store(data, for: .tasks)
  }

  /// Backward compatible method for recording task completion
  public func recordTaskCompletion(taskId: String) {
    guard UUID(uuidString: taskId) != nil else { return }
    let operation = WidgetPendingOperation(itemId: taskId, action: TaskWidgetAction.complete)
    recordPendingOperation(operation, for: .tasks)
  }

  /// Backward compatible method for recording add task intent
  public func recordAddTaskIntent() {
    let operation = WidgetPendingOperation(itemId: "", action: TaskWidgetAction.addNew)
    recordPendingOperation(operation, for: .tasks)
  }

  // MARK: - Quick Save

  private static let pendingQuickSaveKey = "pendingQuickSaveURL"

  /// Records a URL to be saved when the app opens
  public func recordPendingQuickSave(url: URL) {
    guard let defaults = userDefaults else { return }
    defaults.set(url.absoluteString, forKey: Self.pendingQuickSaveKey)
    defaults.synchronize()
  }

  /// Consumes the pending quick save URL (called by main app)
  public func consumePendingQuickSave() -> URL? {
    guard let defaults = userDefaults,
          let urlString = defaults.string(forKey: Self.pendingQuickSaveKey),
          let url = URL(string: urlString) else {
      return nil
    }
    defaults.removeObject(forKey: Self.pendingQuickSaveKey)
    defaults.synchronize()
    return url
  }
}
