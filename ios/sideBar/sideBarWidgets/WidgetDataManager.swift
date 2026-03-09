import Foundation
import WidgetKit

/// Lightweight widget data manager for extension use only.
/// Supports read operations and recording pending operations.
public final class WidgetDataManager {
  public static let shared = WidgetDataManager()

  private let authKey = "widgetIsAuthenticated"
  private let diagnosticsKey = "externalSurfaceDiagnostics"
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
    let normalized = [
      ".sideBar-Safari-Extension--macOS-.Extension",
      ".sideBar-Safari-Extension--macOS-",
      ".sideBar-Safari-Extension",
      ".sideBarWidgets",
      ".ShareExtension"
    ].reduce(bundleId) { partial, suffix in
      partial.replacingOccurrences(of: suffix, with: "")
    }
    return "group.\(normalized)"
  }

  // MARK: - Generic Data Storage

  /// Loads widget data for a content type
  public func load<T: WidgetDataContainer>(for contentType: WidgetContentType) -> T {
    guard let defaults = userDefaults,
          let data = defaults.data(forKey: contentType.dataKey) else {
      recordDiagnostics(
        stage: "load_empty",
        message: "No widget data snapshot was available.",
        metadata: ["content_type": contentType.rawValue]
      )
      return T.empty
    }
    recordDiagnostics(
      stage: "load",
      message: "Loaded widget data snapshot.",
      metadata: [
        "content_type": contentType.rawValue,
        "bytes": "\(data.count)"
      ]
    )
    return (try? Self.makeDecoder().decode(T.self, from: data)) ?? T.empty
  }

  /// Stores widget data for a content type (used for optimistic updates from intents)
  public func store<T: WidgetDataContainer>(_ data: T, for contentType: WidgetContentType) {
    guard let defaults = userDefaults else { return }
    if let encoded = try? Self.makeEncoder().encode(data) {
      defaults.set(encoded, forKey: contentType.dataKey)
      defaults.synchronize()
      recordDiagnostics(
        stage: "store",
        message: "Stored widget data snapshot.",
        metadata: [
          "content_type": contentType.rawValue,
          "bytes": "\(encoded.count)"
        ]
      )
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
        recordDiagnostics(
          stage: "record_pending_operation",
          message: "Recorded widget pending operation.",
          metadata: [
            "content_type": contentType.rawValue,
            "count": "\(pending.count)"
          ]
        )
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
    let isAuthenticated = userDefaults?.bool(forKey: authKey) ?? false
    recordDiagnostics(
      stage: "read_auth_state",
      message: "Read widget auth state.",
      metadata: ["is_authenticated": isAuthenticated ? "true" : "false"]
    )
    return isAuthenticated
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
    recordDiagnostics(
      stage: "record_pending_quick_save",
      message: "Recorded widget quick save URL.",
      metadata: ["url": url.absoluteString]
    )
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
    recordDiagnostics(
      stage: "consume_pending_quick_save",
      message: "Consumed widget quick save URL.",
      metadata: ["url": url.absoluteString]
    )
    return url
  }
}

private extension WidgetDataManager {
  func recordDiagnostics(
    stage: String,
    message: String,
    metadata: [String: String] = [:]
  ) {
    guard let defaults = userDefaults else { return }
    var entries = loadDiagnosticEntries(defaults: defaults)
    entries.append(
      WidgetDiagnosticEntry(
        surface: "widget_bridge_extension",
        stage: stage,
        message: message,
        metadata: metadata.merging(
          [
            "bundle_id": Bundle.main.bundleIdentifier ?? "nil",
            "app_group_id": appGroupId
          ],
          uniquingKeysWith: { current, _ in current }
        )
      )
    )
    if entries.count > 200 {
      entries.removeFirst(entries.count - 200)
    }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    if let data = try? encoder.encode(entries) {
      defaults.set(data, forKey: diagnosticsKey)
      defaults.synchronize()
    }
  }

  func loadDiagnosticEntries(defaults: UserDefaults) -> [WidgetDiagnosticEntry] {
    guard let data = defaults.data(forKey: diagnosticsKey) else { return [] }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (try? decoder.decode([WidgetDiagnosticEntry].self, from: data)) ?? []
  }
}

private struct WidgetDiagnosticEntry: Codable, Equatable {
  let timestamp: Date
  let surface: String
  let stage: String
  let message: String
  let metadata: [String: String]

  init(
    timestamp: Date = Date(),
    surface: String,
    stage: String,
    message: String,
    metadata: [String: String]
  ) {
    self.timestamp = timestamp
    self.surface = surface
    self.stage = stage
    self.message = message
    self.metadata = metadata
  }
}
