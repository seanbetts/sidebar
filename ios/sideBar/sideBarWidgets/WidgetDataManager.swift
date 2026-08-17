import Foundation
import WidgetKit
import sideBarShared

/// Lightweight widget data manager for extension use only.
/// Supports read operations and recording pending operations.
public final class WidgetDataManager {
  public static let shared = WidgetDataManager()

  private let authKey = "widgetIsAuthenticated"
  private let displayStateKey = WidgetDisplayAuthorization.displayStateStorageKey
  private let faviconR2EndpointKey = "widget_favicon_r2_endpoint"
  private let faviconR2BucketKey = "widget_favicon_r2_bucket"
  private let faviconR2PublicBaseUrlKey = "widget_favicon_r2_public_base_url"
  private let taskConfigurationCatalogKey = "widget_tasks_configuration_catalog"
  private let noteConfigurationCatalogKey = "widget_notes_configuration_catalog"
  private let injectedUserDefaults: UserDefaults?

  // Legacy keys (for backward compatibility during transition)
  private let legacyTodayTasksKey = "widgetTodayTasks"
  private let legacyPendingCompletionsKey = "widgetPendingCompletions"
  private let legacyPendingAddTaskKey = "widgetPendingAddTask"

  public init(userDefaults: UserDefaults? = nil) {
    self.injectedUserDefaults = userDefaults
  }

  // MARK: - App Group Access

  private var userDefaults: UserDefaults? {
    if let injectedUserDefaults {
      return injectedUserDefaults
    }
    guard let groupId = appGroupResolution.id else { return nil }
    return UserDefaults(suiteName: groupId)
  }

  private var appGroupId: String? {
    appGroupResolution.id
  }

  private var appGroupResolution: WidgetBridgeAppGroupResolution {
    WidgetBridgeAppGroupResolver.resolve(
      configuredValue: Bundle.main.object(forInfoDictionaryKey: "APP_GROUP_ID") as? String,
      bundleIdentifier: Bundle.main.bundleIdentifier
    )
  }

  private var bridge: WidgetDataBridge {
    WidgetDataBridge(
      userDefaultsProvider: { [self] in userDefaults },
      appGroupResolutionProvider: { [self] in appGroupResolution },
      diagnosticsRecorder: { [self] stage, message, metadata in
        recordDiagnostics(stage: stage, message: message, metadata: metadata)
      },
      timelineReloader: { contentType in
        for kind in contentType.widgetKinds {
          WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
      }
    )
  }

  // MARK: - Generic Data Storage

  /// Loads widget data for a content type
  public func load<T: WidgetDataContainer>(for contentType: WidgetContentType) -> T {
    bridge.load(for: contentType)
  }

  public func hasStoredSnapshot(for contentType: WidgetContentType) -> Bool {
    bridge.hasStoredSnapshot(for: contentType)
  }

  /// Stores widget data for a content type (used for optimistic updates from intents)
  public func store<T: WidgetDataContainer>(_ data: T, for contentType: WidgetContentType) {
    bridge.store(data, for: contentType)
  }

  // MARK: - Generic Pending Operations

  /// Records a pending operation from widget
  public func recordPendingOperation<A: Codable & Equatable>(
    _ operation: WidgetPendingOperation<A>,
    for contentType: WidgetContentType
  ) {
    bridge.recordPendingOperation(operation, for: contentType)
  }

  public func loadPendingOperations<A: Codable & Equatable>(
    for contentType: WidgetContentType,
    actionType: A.Type
  ) -> [WidgetPendingOperation<A>] {
    bridge.loadPendingOperations(for: contentType, actionType: actionType)
  }

  public func removePendingOperation<A: Codable & Equatable>(
    withId operationId: String,
    for contentType: WidgetContentType,
    actionType: A.Type
  ) {
    bridge.removePendingOperation(
      withId: operationId,
      for: contentType,
      actionType: actionType
    )
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

  public func storedDisplayState() -> WidgetDisplayAuthorization.DisplayState? {
    guard let rawValue = userDefaults?.string(forKey: displayStateKey) else { return nil }
    return WidgetDisplayAuthorization.DisplayState(rawValue: rawValue)
  }

  public func displayState(hasCachedSnapshot: Bool) -> WidgetDisplayAuthorization.DisplayState {
    WidgetDisplayAuthorization.displayState(
      storedState: storedDisplayState(),
      isAuthenticated: isAuthenticated(),
      hasCachedSnapshot: hasCachedSnapshot
    )
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

  public func loadTaskConfigurationCatalog() -> WidgetTaskConfigurationCatalog {
    guard let defaults = userDefaults,
          let encoded = defaults.data(forKey: taskConfigurationCatalogKey),
          let decoded = try? Self.makeDecoder().decode(WidgetTaskConfigurationCatalog.self, from: encoded) else {
      return .empty
    }
    return decoded
  }

  public func loadNoteConfigurationCatalog() -> WidgetNoteConfigurationCatalog {
    guard let defaults = userDefaults,
          let encoded = defaults.data(forKey: noteConfigurationCatalogKey),
          let decoded = try? Self.makeDecoder().decode(WidgetNoteConfigurationCatalog.self, from: encoded) else {
      return .empty
    }
    return decoded
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
  private var configuredTaskDataKeyPrefix: String {
    "widget_tasks_data::"
  }

  func loadTaskData(for selection: TaskWidgetSelection) -> WidgetTaskData {
    if selection == .today {
      return loadTodayTasks()
    }
    guard let defaults = userDefaults else {
      return .empty
    }
    for key in taskSnapshotKeys(for: selection) {
      guard let data = defaults.data(forKey: key),
            let decoded = try? Self.makeDecoder().decode(WidgetTaskData.self, from: data) else {
        continue
      }
      return decoded
    }
    return .empty
  }

  func hasStoredTaskSnapshot(for selection: TaskWidgetSelection) -> Bool {
    if selection == .today {
      return hasStoredSnapshot(for: .tasks)
    }
    guard let defaults = userDefaults else { return false }
    return taskSnapshotKeys(for: selection).contains { defaults.data(forKey: $0) != nil }
  }

  func storeTaskData(_ data: WidgetTaskData, for selection: TaskWidgetSelection) {
    if selection == .today {
      store(data, for: .tasks)
      return
    }
    guard let defaults = userDefaults,
          let encoded = try? Self.makeEncoder().encode(data) else { return }
    defaults.set(encoded, forKey: configuredTaskDataKeyPrefix + selection.cacheKey)
    for kind in WidgetContentType.tasks.widgetKinds {
      WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }
  }

  func updateTaskData(
    _ tasks: [WidgetTask],
    for selection: TaskWidgetSelection,
    totalCount: Int,
    progressCompletedCount: Int? = nil,
    progressTotalCount: Int? = nil
  ) {
    let existing = loadTaskData(for: selection)
    let data = WidgetTaskData(
      tasks: tasks,
      totalCount: totalCount,
      progressCompletedCount: progressCompletedCount ?? existing.progressCompletedCount,
      progressTotalCount: progressTotalCount ?? max(totalCount, existing.progressTotalCount),
      optimisticallyCompletedTaskIds: existing.optimisticallyCompletedTaskIds,
      pendingOptimisticCompletionTaskIds: existing.pendingOptimisticCompletionTaskIds
    )
    storeTaskData(data, for: selection)
  }

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
    updateTaskData(
      tasks,
      for: .today,
      totalCount: totalCount,
      progressCompletedCount: progressCompletedCount,
      progressTotalCount: progressTotalCount
    )
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
    WidgetIntentHandoffNotifier.post()
  }

  /// Backward compatible method for recording add note intent
  public func recordAddNoteIntent() {
    let operation = WidgetPendingOperation(itemId: "", action: NoteWidgetAction.addNew)
    recordPendingOperation(operation, for: .notes)
    WidgetIntentHandoffNotifier.post()
  }

  private func taskSnapshotKeys(for selection: TaskWidgetSelection) -> [String] {
    switch selection {
    case .today:
      return [WidgetContentType.tasks.dataKey]
    case .project(let id, _):
      return [
        configuredTaskDataKeyPrefix + selection.cacheKey,
        configuredTaskDataKeyPrefix + "project:\(id)"
      ]
    case .group(let id, _):
      return [
        configuredTaskDataKeyPrefix + selection.cacheKey,
        configuredTaskDataKeyPrefix + "group:\(id)"
      ]
    }
  }

}

private extension WidgetDataManager {
  func recordDiagnostics(
    stage: String,
    message: String,
    metadata: [String: String] = [:]
  ) {
    let mergedMetadata = metadata.merging(
      [
        "app_group_id": appGroupId ?? "nil",
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
