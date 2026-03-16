import Foundation
import WidgetKit
import sideBarShared

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
    UserDefaults(suiteName: appGroupResolution.id)
  }

  private var appGroupId: String {
    appGroupResolution.id
  }

  private var appGroupResolution: (id: String, source: String) {
    if let configured = configuredAppGroupId() {
      return (configured, "info_plist")
    }
    if let derived = AppGroupConfiguration.resolvedAppGroupId(bundleIdentifier: Bundle.main.bundleIdentifier) {
      return (derived, "bundle_identifier")
    }
    return ("group.ai.sidebar.sidebar", "hardcoded_fallback")
  }

  // MARK: - Generic Data Storage

  /// Loads widget data for a content type
  public func load<T: WidgetDataContainer>(for contentType: WidgetContentType) -> T {
    let resolution = appGroupResolution
    guard let defaults = userDefaults else {
      recordDiagnostics(
        stage: "load_empty",
        message: "No widget data snapshot was available.",
        metadata: [
          "content_type": contentType.rawValue,
          "app_group_source": resolution.source,
          "has_defaults": "false",
          "has_data_key": "false"
        ]
      )
      return T.empty
    }

    guard let data = defaults.data(forKey: contentType.dataKey) else {
      recordDiagnostics(
        stage: "load_empty",
        message: "No widget data snapshot was available.",
        metadata: [
          "content_type": contentType.rawValue,
          "app_group_source": resolution.source,
          "has_defaults": "true",
          "has_data_key": defaults.object(forKey: contentType.dataKey) == nil ? "false" : "true"
        ]
      )
      return T.empty
    }

    let decoded = try? Self.makeDecoder().decode(T.self, from: data)
    recordDiagnostics(
      stage: "load",
      message: "Loaded widget data snapshot.",
      metadata: [
        "content_type": contentType.rawValue,
        "app_group_source": resolution.source,
        "has_defaults": "true",
        "has_data_key": "true",
        "bytes": "\(data.count)",
        "decode_success": decoded == nil ? "false" : "true",
        "item_count": "\(decoded?.items.count ?? 0)",
        "total_count": "\(decoded?.totalCount ?? 0)"
      ]
    )
    return decoded ?? T.empty
  }

  /// Stores widget data for a content type (used for optimistic updates from intents)
  public func store<T: WidgetDataContainer>(_ data: T, for contentType: WidgetContentType) {
    let resolution = appGroupResolution
    guard let defaults = userDefaults else {
      recordDiagnostics(
        stage: "store_missing_defaults",
        message: "Could not store widget data snapshot because shared defaults were unavailable.",
        metadata: [
          "content_type": contentType.rawValue,
          "app_group_source": resolution.source,
          "has_defaults": "false"
        ]
      )
      return
    }
    if let encoded = try? Self.makeEncoder().encode(data) {
      defaults.set(encoded, forKey: contentType.dataKey)
      defaults.synchronize()
      recordDiagnostics(
        stage: "store",
        message: "Stored widget data snapshot.",
        metadata: [
          "content_type": contentType.rawValue,
          "app_group_source": resolution.source,
          "has_defaults": "true",
          "bytes": "\(encoded.count)",
          "item_count": "\(data.items.count)",
          "total_count": "\(data.totalCount)"
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
      metadata: [
        "app_group_source": appGroupResolution.source,
        "has_defaults": userDefaults == nil ? "false" : "true",
        "auth_key_present": userDefaults?.object(forKey: authKey) == nil ? "false" : "true",
        "is_authenticated": isAuthenticated ? "true" : "false"
      ]
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

  private func configuredAppGroupId() -> String? {
    let raw = Bundle.main.object(forInfoDictionaryKey: "APP_GROUP_ID") as? String
    let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmed.isEmpty, !trimmed.contains("$(") else {
      return nil
    }
    return trimmed
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
    WidgetTaskCompletionHandoffNotifier.post()
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
    WidgetExtensionDiagnostics.ensureSentryStarted()
    let mergedMetadata = metadata.merging(
      [
        "app_group_id": appGroupId,
        "app_group_source": appGroupResolution.source
      ],
      uniquingKeysWith: { current, _ in current }
    )
    let reporter = WidgetExtensionDiagnostics.reporter
    switch stage {
    case "store_missing_defaults":
      reporter.captureFailure(
        surface: "widget_bridge_extension",
        stage: stage,
        message: message,
        metadata: mergedMetadata
      )
    case "load_empty" where mergedMetadata["has_defaults"] == "false":
      reporter.captureFailure(
        surface: "widget_bridge_extension",
        stage: stage,
        message: message,
        metadata: mergedMetadata
      )
    case "load" where mergedMetadata["decode_success"] == "false":
      reporter.captureFailure(
        surface: "widget_bridge_extension",
        stage: stage,
        message: message,
        metadata: mergedMetadata
      )
    default:
      reporter.recordBreadcrumb(
        surface: "widget_bridge_extension",
        stage: stage,
        message: message,
        metadata: mergedMetadata
      )
    }
  }
}
