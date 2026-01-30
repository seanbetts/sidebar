import Foundation
import sideBarShared
#if canImport(WidgetKit)
import WidgetKit
#endif

// MARK: - Widget Task Models

/// Lightweight task model for widgets (subset of TaskItem)
public struct WidgetTask: WidgetStorable {
  public let id: String
  public let title: String
  public let isCompleted: Bool
  public let projectName: String?
  public let hasNotes: Bool
  public let deadline: String?

  public init(
    id: String,
    title: String,
    isCompleted: Bool = false,
    projectName: String? = nil,
    hasNotes: Bool = false,
    deadline: String? = nil
  ) {
    self.id = id
    self.title = title
    self.isCompleted = isCompleted
    self.projectName = projectName
    self.hasNotes = hasNotes
    self.deadline = deadline
  }
}

/// Data snapshot for widgets
public struct WidgetTaskData: WidgetDataContainer {
  public typealias Item = WidgetTask

  public let tasks: [WidgetTask]
  public let totalCount: Int
  public let lastUpdated: Date

  public var items: [WidgetTask] { tasks }

  public init(tasks: [WidgetTask], totalCount: Int, lastUpdated: Date = Date()) {
    self.tasks = tasks
    self.totalCount = totalCount
    self.lastUpdated = lastUpdated
  }

  public static let empty = WidgetTaskData(tasks: [], totalCount: 0)

  public static let placeholder = WidgetTaskData(
    tasks: [
      WidgetTask(id: "1", title: "Review project proposal", projectName: "Work", deadline: "2026-01-25"),
      WidgetTask(id: "2", title: "Call dentist", hasNotes: true, deadline: "2026-01-26"),
      WidgetTask(id: "3", title: "Buy groceries"),
      WidgetTask(id: "4", title: "Prepare presentation", projectName: "Work", deadline: "2026-01-27")
    ],
    totalCount: 6
  )
}

// MARK: - Widget Data Manager

/// Manages shared data between the main app and widgets via App Group UserDefaults.
public final class WidgetDataManager {
  public static let shared = WidgetDataManager()

  private let authKey = "widgetIsAuthenticated"
  private let migrationKey = "widget_migration_v2"

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

// MARK: - Backward Compatibility (Deprecated)

extension WidgetDataManager {
  /// Backward compatible method for tasks
  @available(*, deprecated, message: "Use store(_:for:) with WidgetTaskData")
  public func updateTodayTasks(_ tasks: [WidgetTask], totalCount: Int) {
    let data = WidgetTaskData(tasks: tasks, totalCount: totalCount)
    store(data, for: .tasks)
  }

  @available(*, deprecated, message: "Use load(for:) with WidgetTaskData")
  public func loadTodayTasks() -> WidgetTaskData {
    load(for: .tasks)
  }

  @available(*, deprecated, message: "Use recordPendingOperation with TaskWidgetAction.complete")
  public func recordTaskCompletion(taskId: String) {
    let operation = WidgetPendingOperation(itemId: taskId, action: TaskWidgetAction.complete)
    recordPendingOperation(operation, for: .tasks)
  }

  @available(*, deprecated, message: "Use consumePendingOperations")
  public func consumePendingCompletions() -> [String] {
    let operations = consumePendingOperations(for: .tasks, actionType: TaskWidgetAction.self)
    return operations
      .filter { $0.action == .complete }
      .map { $0.itemId }
  }

  @available(*, deprecated, message: "Use recordPendingOperation with TaskWidgetAction.addNew")
  public func recordAddTaskIntent() {
    let operation = WidgetPendingOperation(itemId: "", action: TaskWidgetAction.addNew)
    recordPendingOperation(operation, for: .tasks)
  }

  @available(*, deprecated, message: "Use consumePendingOperations")
  public func consumeAddTaskIntent() -> Bool {
    let operations = consumePendingOperations(for: .tasks, actionType: TaskWidgetAction.self)
    return operations.contains { $0.action == .addNew }
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
    self.deadline = task.deadline
  }
}

// MARK: - WidgetNote Models

/// Lightweight note model for widgets
public struct WidgetNote: WidgetStorable {
  public let id: String
  public let name: String
  public let contentPreview: String?
  public let path: String
  public let modifiedAt: Date?
  public let pinned: Bool
  public let pinnedOrder: Int?

  public init(
    id: String,
    name: String,
    contentPreview: String? = nil,
    path: String,
    modifiedAt: Date? = nil,
    pinned: Bool = false,
    pinnedOrder: Int? = nil
  ) {
    self.id = id
    self.name = name
    self.contentPreview = contentPreview
    self.path = path
    self.modifiedAt = modifiedAt
    self.pinned = pinned
    self.pinnedOrder = pinnedOrder
  }
}

/// Data snapshot for note widgets
public struct WidgetNoteData: WidgetDataContainer {
  public typealias Item = WidgetNote

  public let notes: [WidgetNote]
  public let totalCount: Int
  public let lastUpdated: Date

  public var items: [WidgetNote] { notes }

  public init(notes: [WidgetNote], totalCount: Int, lastUpdated: Date = Date()) {
    self.notes = notes
    self.totalCount = totalCount
    self.lastUpdated = lastUpdated
  }

  public static let empty = WidgetNoteData(notes: [], totalCount: 0)

  public static let placeholder = WidgetNoteData(
    notes: [
      WidgetNote(
        id: "1", name: "Meeting Notes", contentPreview: "Discussed project timeline...",
        path: "/notes/meeting.md", pinned: true, pinnedOrder: 0
      ),
      WidgetNote(
        id: "2", name: "Ideas", contentPreview: "New feature concepts",
        path: "/notes/ideas.md", pinned: true, pinnedOrder: 1
      )
    ],
    totalCount: 2
  )
}

// MARK: - WidgetWebsite Models

/// Lightweight website model for widgets
public struct WidgetWebsite: WidgetStorable {
  public let id: String
  public let title: String
  public let url: String
  public let domain: String
  public let pinned: Bool
  public let pinnedOrder: Int?
  public let archived: Bool

  public init(
    id: String,
    title: String,
    url: String,
    domain: String,
    pinned: Bool = false,
    pinnedOrder: Int? = nil,
    archived: Bool = false
  ) {
    self.id = id
    self.title = title
    self.url = url
    self.domain = domain
    self.pinned = pinned
    self.pinnedOrder = pinnedOrder
    self.archived = archived
  }
}

/// Data snapshot for website widgets
public struct WidgetWebsiteData: WidgetDataContainer {
  public typealias Item = WidgetWebsite

  public let websites: [WidgetWebsite]
  public let totalCount: Int
  public let lastUpdated: Date

  public var items: [WidgetWebsite] { websites }

  public init(websites: [WidgetWebsite], totalCount: Int, lastUpdated: Date = Date()) {
    self.websites = websites
    self.totalCount = totalCount
    self.lastUpdated = lastUpdated
  }

  public static let empty = WidgetWebsiteData(websites: [], totalCount: 0)

  public static let placeholder = WidgetWebsiteData(
    websites: [
      WidgetWebsite(id: "1", title: "Apple", url: "https://apple.com", domain: "apple.com"),
      WidgetWebsite(id: "2", title: "GitHub", url: "https://github.com", domain: "github.com")
    ],
    totalCount: 5
  )
}

// MARK: - FileNode to WidgetNote Conversion

extension WidgetNote {
  /// Creates a WidgetNote from a FileNode
  public init(from node: FileNode) {
    self.id = node.path
    self.name = node.name.hasSuffix(".md") ? String(node.name.dropLast(3)) : node.name
    self.contentPreview = nil
    self.path = node.path
    self.modifiedAt = node.modified.map { Date(timeIntervalSince1970: $0) }
    self.pinned = node.pinned ?? false
    self.pinnedOrder = node.pinnedOrder
  }
}

// MARK: - WebsiteItem to WidgetWebsite Conversion

extension WidgetWebsite {
  /// Creates a WidgetWebsite from a WebsiteItem
  public init(from item: WebsiteItem) {
    self.id = item.id
    self.title = item.title
    self.url = item.url
    self.domain = item.domain
    self.pinned = item.pinned
    self.pinnedOrder = item.pinnedOrder
    self.archived = item.archived
  }
}
