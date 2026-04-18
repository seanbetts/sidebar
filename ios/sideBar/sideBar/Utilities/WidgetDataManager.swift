import Foundation
import sideBarShared
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Manages shared data between the main app and widgets via App Group UserDefaults.
public final class WidgetDataManager {
  public static let shared = WidgetDataManager()

  private let authKey = "widgetIsAuthenticated"
  private let migrationKey = "widget_migration_v2"
  private let faviconR2EndpointKey = "widget_favicon_r2_endpoint"
  private let faviconR2BucketKey = "widget_favicon_r2_bucket"
  private let faviconR2PublicBaseUrlKey = "widget_favicon_r2_public_base_url"
  private let configuredTaskDataKeyPrefix = "widget_tasks_data::"
  private let taskConfigurationCatalogKey = "widget_tasks_configuration_catalog"
  private let noteConfigurationCatalogKey = "widget_notes_configuration_catalog"

  // Legacy keys (for migration)
  private let legacyTodayTasksKey = "widgetTodayTasks"
  private let legacyPendingCompletionsKey = "widgetPendingCompletions"
  private let legacyPendingAddTaskKey = "widgetPendingAddTask"
  private let injectedUserDefaults: UserDefaults?

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
      timelineReloader: { [self] contentType in
        reloadWidgets(for: contentType)
      }
    )
  }

  // MARK: - Generic Data Storage

  /// Stores widget data for a content type
  public func store<T: WidgetDataContainer>(_ data: T, for contentType: WidgetContentType) {
    bridge.store(data, for: contentType)
  }

  /// Loads widget data for a content type
  public func load<T: WidgetDataContainer>(for contentType: WidgetContentType) -> T {
    bridge.load(for: contentType)
  }

  public func hasStoredSnapshot(for contentType: WidgetContentType) -> Bool {
    bridge.hasStoredSnapshot(for: contentType)
  }

  // MARK: - Generic Pending Operations

  /// Records a pending operation from widget
  public func recordPendingOperation<A: Codable & Equatable>(
    _ operation: WidgetPendingOperation<A>,
    for contentType: WidgetContentType
  ) {
    bridge.recordPendingOperation(operation, for: contentType)
  }

  /// Consumes and clears pending operations (called by main app)
  public func consumePendingOperations<A: Codable & Equatable>(
    for contentType: WidgetContentType,
    actionType: A.Type
  ) -> [WidgetPendingOperation<A>] {
    bridge.consumePendingOperations(for: contentType, actionType: actionType)
  }

  /// Consumes matching pending operations and preserves non-matching operations.
  public func consumePendingOperations<A: Codable & Equatable>(
    for contentType: WidgetContentType,
    actionType: A.Type,
    matching: (A) -> Bool
  ) -> [WidgetPendingOperation<A>] {
    bridge.consumePendingOperations(for: contentType, actionType: actionType, matching: matching)
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

  /// Called by main app when auth state changes
  public func updateAuthState(isAuthenticated: Bool) {
    guard let defaults = userDefaults else { return }
    defaults.set(isAuthenticated, forKey: authKey)
    recordDiagnostics(
      stage: "update_auth_state",
      message: "Updated widget auth state.",
      metadata: ["is_authenticated": isAuthenticated ? "true" : "false"]
    )
    reloadAllWidgets()
  }

  /// Clears shared widget snapshots and pending operations on sign-out.
  public func clearAllDataForSignOut() {
    guard let defaults = userDefaults else { return }
    defaults.set(false, forKey: authKey)

    for contentType in WidgetContentType.allCases {
      defaults.removeObject(forKey: contentType.dataKey)
      defaults.removeObject(forKey: contentType.pendingKey)
    }
    for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(configuredTaskDataKeyPrefix) {
      defaults.removeObject(forKey: key)
    }
    defaults.removeObject(forKey: taskConfigurationCatalogKey)
    defaults.removeObject(forKey: noteConfigurationCatalogKey)

    defaults.removeObject(forKey: legacyTodayTasksKey)
    defaults.removeObject(forKey: legacyPendingCompletionsKey)
    defaults.removeObject(forKey: legacyPendingAddTaskKey)
    recordDiagnostics(
      stage: "clear_all_for_sign_out",
      message: "Cleared widget bridge data for sign-out."
    )
    reloadAllWidgets()
  }

  /// Called by widgets to check auth state
  public func isAuthenticated() -> Bool {
    guard let defaults = userDefaults else { return false }
    return defaults.bool(forKey: authKey)
  }

  /// Called by main app to share favicon URL configuration with widgets.
  public func updateFaviconConfiguration(
    r2Endpoint: URL?,
    r2FaviconBucket: String?,
    r2FaviconPublicBaseUrl: URL?
  ) {
    guard let defaults = userDefaults else { return }
    setOptionalString(r2Endpoint?.absoluteString, forKey: faviconR2EndpointKey, in: defaults)
    setOptionalString(r2FaviconBucket, forKey: faviconR2BucketKey, in: defaults)
    setOptionalString(r2FaviconPublicBaseUrl?.absoluteString, forKey: faviconR2PublicBaseUrlKey, in: defaults)
    recordDiagnostics(
      stage: "update_favicon_configuration",
      message: "Updated widget favicon configuration.",
      metadata: [
        "has_endpoint": r2Endpoint == nil ? "false" : "true",
        "has_bucket": (r2FaviconBucket?.isEmpty == false) ? "true" : "false",
        "has_public_base": r2FaviconPublicBaseUrl == nil ? "false" : "true"
      ]
    )
    reloadWidgets(for: .websites)
  }

  // MARK: - Migration

  /// Migrates data from legacy keys to new generic keys (call on app startup)
  public func migrateIfNeeded() {
    guard let defaults = userDefaults else { return }
    guard !defaults.bool(forKey: migrationKey) else { return }

    // Migrate task data
    if let oldData = defaults.data(forKey: legacyTodayTasksKey) {
      defaults.set(oldData, forKey: WidgetContentType.tasks.dataKey)
      defaults.removeObject(forKey: legacyTodayTasksKey)
    }

    // Migrate pending completions to new format
    if let oldData = defaults.data(forKey: legacyPendingCompletionsKey),
       let oldIds = try? JSONDecoder().decode([String].self, from: oldData) {
      let newOperations = oldIds.map {
        WidgetPendingOperation(itemId: $0, action: TaskWidgetAction.complete)
      }
      if let encoded = try? Self.makeEncoder().encode(newOperations) {
        defaults.set(encoded, forKey: WidgetContentType.tasks.pendingKey)
      }
      defaults.removeObject(forKey: legacyPendingCompletionsKey)
    }

    // Migrate pending add task intent
    if defaults.bool(forKey: legacyPendingAddTaskKey) {
      var pending = loadPendingOperations(for: .tasks, actionType: TaskWidgetAction.self)
      pending.append(WidgetPendingOperation(itemId: "", action: TaskWidgetAction.addNew))
      if let encoded = try? Self.makeEncoder().encode(pending) {
        defaults.set(encoded, forKey: WidgetContentType.tasks.pendingKey)
      }
      defaults.removeObject(forKey: legacyPendingAddTaskKey)
    }

    defaults.set(true, forKey: migrationKey)
  }

  /// Removes invalid pending task completion operations that can never be applied server-side.
  public func sanitizePendingTaskCompletions() {
    guard let defaults = userDefaults else { return }
    let pending = loadPendingOperations(for: .tasks, actionType: TaskWidgetAction.self)
    guard !pending.isEmpty else { return }

    let filtered = pending.filter { operation in
      guard operation.action == .complete else { return true }
      let itemId = operation.itemId.trimmingCharacters(in: .whitespacesAndNewlines)
      return IdentifierValidation.isServerTaskID(itemId)
    }

    if filtered.count == pending.count {
      return
    }

    if filtered.isEmpty {
      defaults.removeObject(forKey: WidgetContentType.tasks.pendingKey)
    } else if let encoded = try? Self.makeEncoder().encode(filtered) {
      defaults.set(encoded, forKey: WidgetContentType.tasks.pendingKey)
    }
  }

  public func updateTaskConfigurationCatalog(
    projects: [TaskProject],
    groups: [TaskGroup]
  ) {
    let existingCatalog = loadTaskConfigurationCatalog()
    let nextProjects: [WidgetTaskConfigurationProject]
    if projects.isEmpty {
      nextProjects = existingCatalog.projects
    } else {
      nextProjects = projects
        .map {
          WidgetTaskConfigurationProject(
            id: $0.id,
            title: $0.title,
            groupId: $0.groupId
          )
        }
        .sorted {
          $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    let nextGroups: [WidgetTaskConfigurationGroup]
    if groups.isEmpty {
      nextGroups = existingCatalog.groups
    } else {
      nextGroups = groups
        .map { WidgetTaskConfigurationGroup(id: $0.id, title: $0.title) }
        .sorted {
          $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    guard let defaults = userDefaults,
          let encoded = try? Self.makeEncoder().encode(
            WidgetTaskConfigurationCatalog(
              projects: nextProjects,
              groups: nextGroups
            )
          ) else {
      return
    }
    defaults.set(encoded, forKey: taskConfigurationCatalogKey)
  }

  public func loadTaskConfigurationCatalog() -> WidgetTaskConfigurationCatalog {
    guard let defaults = userDefaults,
          let encoded = defaults.data(forKey: taskConfigurationCatalogKey),
          let decoded = try? Self.makeDecoder().decode(WidgetTaskConfigurationCatalog.self, from: encoded) else {
      return .empty
    }
    return decoded
  }

  public func updateNoteConfigurationCatalog(from tree: FileTree) {
    guard let defaults = userDefaults,
          let encoded = try? Self.makeEncoder().encode(
            WidgetNoteConfigurationCatalog(
              folders: noteConfigurationFolders(from: tree.children)
            )
          ) else {
      return
    }
    defaults.set(encoded, forKey: noteConfigurationCatalogKey)
  }

  public func loadNoteConfigurationCatalog() -> WidgetNoteConfigurationCatalog {
    guard let defaults = userDefaults,
          let encoded = defaults.data(forKey: noteConfigurationCatalogKey),
          let decoded = try? Self.makeDecoder().decode(WidgetNoteConfigurationCatalog.self, from: encoded) else {
      return .empty
    }
    return decoded
  }

  // MARK: - Widget Reload

  private func reloadWidgets(for contentType: WidgetContentType) {
    #if canImport(WidgetKit)
    recordDiagnostics(
      stage: "reload_timelines",
      message: "Requested widget timeline reload.",
      metadata: [
        "content_type": contentType.rawValue,
        "widget_kinds": contentType.widgetKinds.joined(separator: ",")
      ]
    )
    for kind in contentType.widgetKinds {
      WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }
    #endif
  }

  private func reloadAllWidgets() {
    #if canImport(WidgetKit)
    recordDiagnostics(
      stage: "reload_all_timelines",
      message: "Requested reload for all widget timelines."
    )
    WidgetCenter.shared.reloadAllTimelines()
    #endif
  }

  // MARK: - Encoder/Decoder

  private func setOptionalString(_ value: String?, forKey key: String, in defaults: UserDefaults) {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if trimmed.isEmpty {
      defaults.removeObject(forKey: key)
      return
    }
    defaults.set(trimmed, forKey: key)
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

// MARK: - Quick Save

extension WidgetDataManager {
  public func loadTaskData(for selection: TaskSelection) -> WidgetTaskData {
    if selection == .today {
      return load(for: .tasks)
    }
    guard let defaults = userDefaults,
          let data = defaults.data(forKey: configuredTaskDataKeyPrefix + selection.cacheKey),
          let decoded = try? Self.makeDecoder().decode(WidgetTaskData.self, from: data) else {
      return .empty
    }
    return decoded
  }

  public func hasStoredTaskSnapshot(for selection: TaskSelection) -> Bool {
    if selection == .today {
      return hasStoredSnapshot(for: .tasks)
    }
    return userDefaults?.data(forKey: configuredTaskDataKeyPrefix + selection.cacheKey) != nil
  }

  public func storeTaskData(_ data: WidgetTaskData, for selection: TaskSelection) {
    if selection == .today {
      store(data, for: .tasks)
      return
    }
    guard let defaults = userDefaults,
          let encoded = try? Self.makeEncoder().encode(data) else { return }
    defaults.set(encoded, forKey: configuredTaskDataKeyPrefix + selection.cacheKey)
    reloadWidgets(for: .tasks)
  }

  /// Records a task completion from a widget and notifies a running app process.
  public func recordTaskCompletion(taskId: String) {
    guard IdentifierValidation.isServerTaskID(taskId) else { return }
    let operation = WidgetPendingOperation(itemId: taskId, action: TaskWidgetAction.complete)
    recordPendingOperation(operation, for: .tasks)
    WidgetTaskCompletionHandoffNotifier.post()
  }

  /// Records an add-task widget intent and notifies a running app process.
  public func recordAddTaskIntent() {
    let operation = WidgetPendingOperation(itemId: "", action: TaskWidgetAction.addNew)
    recordPendingOperation(operation, for: .tasks)
    WidgetIntentHandoffNotifier.post()
  }

  /// Records an add-note widget intent and notifies a running app process.
  public func recordAddNoteIntent() {
    let operation = WidgetPendingOperation(itemId: "", action: NoteWidgetAction.addNew)
    recordPendingOperation(operation, for: .notes)
    WidgetIntentHandoffNotifier.post()
  }

  private func noteConfigurationFolders(from nodes: [FileNode]) -> [WidgetNoteConfigurationFolder] {
    var folders: [WidgetNoteConfigurationFolder] = []

    for node in nodes {
      guard node.type == .directory else { continue }
      if node.name.lowercased() == "archive" { continue }

      let normalizedPath = normalizeWidgetFolderPath(node.path)
      folders.append(
        WidgetNoteConfigurationFolder(
          id: normalizedPath,
          title: node.name,
          path: normalizedPath
        )
      )

      if let children = node.children {
        folders.append(contentsOf: noteConfigurationFolders(from: children))
      }
    }

    return folders.sorted {
      $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
    }
  }

  private func normalizeWidgetFolderPath(_ path: String) -> String {
    let trimmed = path
      .replacingOccurrences(of: "folder:", with: "")
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard !trimmed.isEmpty else { return "/" }
    return "/" + trimmed
  }

}

private extension WidgetDataManager {
  func recordDiagnostics(
    stage: String,
    message: String,
    metadata: [String: String] = [:]
  ) {
    ExternalSurfaceDiagnosticsStore.shared.record(
      surface: "widget_bridge_app",
      stage: stage,
      message: message,
      metadata: metadata.merging(
        [
          "app_group_id": appGroupId ?? "nil",
          "app_group_source": appGroupResolution.source
        ],
        uniquingKeysWith: { current, _ in current }
      )
    )
  }
}
