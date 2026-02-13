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

  // Legacy keys (for migration)
  private let legacyTodayTasksKey = "widgetTodayTasks"
  private let legacyPendingCompletionsKey = "widgetPendingCompletions"
  private let legacyPendingAddTaskKey = "widgetPendingAddTask"

  private init() {}

  // MARK: - App Group Access

  private var userDefaults: UserDefaults? {
    guard let groupId = appGroupId else { return nil }
    return UserDefaults(suiteName: groupId)
  }

  private var appGroupId: String? {
    AppGroupConfiguration.appGroupId
  }

  // MARK: - Generic Data Storage

  /// Stores widget data for a content type
  public func store<T: WidgetDataContainer>(_ data: T, for contentType: WidgetContentType) {
    guard let defaults = userDefaults else { return }
    if let encoded = try? Self.makeEncoder().encode(data) {
      defaults.set(encoded, forKey: contentType.dataKey)
      defaults.synchronize()
    }
    reloadWidgets(for: contentType)
  }

  /// Loads widget data for a content type
  public func load<T: WidgetDataContainer>(for contentType: WidgetContentType) -> T {
    guard let defaults = userDefaults,
          let data = defaults.data(forKey: contentType.dataKey) else {
      return T.empty
    }
    return (try? Self.makeDecoder().decode(T.self, from: data)) ?? T.empty
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

  /// Consumes and clears pending operations (called by main app)
  public func consumePendingOperations<A: Codable & Equatable>(
    for contentType: WidgetContentType,
    actionType: A.Type
  ) -> [WidgetPendingOperation<A>] {
    guard let defaults = userDefaults else { return [] }
    let pending = loadPendingOperations(for: contentType, actionType: actionType)
    defaults.removeObject(forKey: contentType.pendingKey)
    defaults.synchronize()
    return pending
  }

  /// Consumes matching pending operations and preserves non-matching operations.
  public func consumePendingOperations<A: Codable & Equatable>(
    for contentType: WidgetContentType,
    actionType: A.Type,
    matching: (A) -> Bool
  ) -> [WidgetPendingOperation<A>] {
    guard let defaults = userDefaults else { return [] }
    let pending = loadPendingOperations(for: contentType, actionType: actionType)
    guard !pending.isEmpty else { return [] }

    let matchingOperations = pending.filter { matching($0.action) }
    let remainingOperations = pending.filter { !matching($0.action) }

    if remainingOperations.isEmpty {
      defaults.removeObject(forKey: contentType.pendingKey)
    } else if let encoded = try? Self.makeEncoder().encode(remainingOperations) {
      defaults.set(encoded, forKey: contentType.pendingKey)
    }
    defaults.synchronize()
    return matchingOperations
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

  /// Called by main app when auth state changes
  public func updateAuthState(isAuthenticated: Bool) {
    guard let defaults = userDefaults else { return }
    defaults.set(isAuthenticated, forKey: authKey)
    defaults.synchronize()
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
    defaults.synchronize()
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
    defaults.synchronize()
  }

  // MARK: - Widget Reload

  private func reloadWidgets(for contentType: WidgetContentType) {
    #if canImport(WidgetKit)
    for kind in contentType.widgetKinds {
      WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }
    #endif
  }

  private func reloadAllWidgets() {
    #if canImport(WidgetKit)
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
