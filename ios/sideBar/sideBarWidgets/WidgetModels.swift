import Foundation

// MARK: - Task Models

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

/// Data snapshot for task widgets
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

// MARK: - Note Models

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
      WidgetNote(id: "1", name: "Meeting Notes", contentPreview: "Discussed project timeline...", path: "/notes/meeting.md", pinned: true, pinnedOrder: 0),
      WidgetNote(id: "2", name: "Ideas", contentPreview: "New feature concepts", path: "/notes/ideas.md", pinned: true, pinnedOrder: 1)
    ],
    totalCount: 2
  )
}

// MARK: - Website Models

/// Lightweight website model for widgets
public struct WidgetWebsite: WidgetStorable {
  public let id: String
  public let title: String
  public let url: String
  public let domain: String
  public let pinned: Bool
  public let archived: Bool

  public init(
    id: String,
    title: String,
    url: String,
    domain: String,
    pinned: Bool = false,
    archived: Bool = false
  ) {
    self.id = id
    self.title = title
    self.url = url
    self.domain = domain
    self.pinned = pinned
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
      WidgetWebsite(id: "1", title: "Apple", url: "https://apple.com", domain: "apple.com", pinned: true),
      WidgetWebsite(id: "2", title: "GitHub", url: "https://github.com", domain: "github.com")
    ],
    totalCount: 10
  )
}

// MARK: - File Models

/// Lightweight file model for widgets
public struct WidgetFile: WidgetStorable {
  public let id: String
  public let filename: String
  public let path: String?
  public let sizeBytes: Int
  public let pinned: Bool
  public let category: String?

  public init(
    id: String,
    filename: String,
    path: String? = nil,
    sizeBytes: Int,
    pinned: Bool = false,
    category: String? = nil
  ) {
    self.id = id
    self.filename = filename
    self.path = path
    self.sizeBytes = sizeBytes
    self.pinned = pinned
    self.category = category
  }
}

/// Data snapshot for file widgets
public struct WidgetFileData: WidgetDataContainer {
  public typealias Item = WidgetFile

  public let files: [WidgetFile]
  public let totalCount: Int
  public let lastUpdated: Date

  public var items: [WidgetFile] { files }

  public init(files: [WidgetFile], totalCount: Int, lastUpdated: Date = Date()) {
    self.files = files
    self.totalCount = totalCount
    self.lastUpdated = lastUpdated
  }

  public static let empty = WidgetFileData(files: [], totalCount: 0)

  public static let placeholder = WidgetFileData(
    files: [
      WidgetFile(id: "1", filename: "Report.pdf", sizeBytes: 1_024_000, pinned: true, category: "Documents"),
      WidgetFile(id: "2", filename: "Notes.txt", sizeBytes: 2048, category: "Text")
    ],
    totalCount: 15
  )
}

// MARK: - Widget Task Ordering

private let widgetTasksDateFormatter: DateFormatter = {
  let formatter = DateFormatter()
  formatter.dateFormat = "yyyy-MM-dd"
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = TimeZone.current
  return formatter
}()

public enum WidgetTasksUtils {
  private static let msPerDay: Double = 24 * 60 * 60

  public static func isOverdue(_ task: WidgetTask) -> Bool {
    guard let date = parseTaskDate(task) else { return false }
    let today = startOfDay(Date())
    return dayDiff(from: today, to: date) < 0
  }

  public static func sortByDueDate(_ tasks: [WidgetTask]) -> [WidgetTask] {
    tasks.sorted { lhs, rhs in
      compareByDueThenTitle(lhs, rhs)
    }
  }

  private static func parseTaskDate(_ task: WidgetTask) -> Date? {
    guard let deadline = task.deadline, deadline.count >= 10 else { return nil }
    let dateKey = String(deadline.prefix(10))
    return widgetTasksDateFormatter.date(from: dateKey)
  }

  private static func compareByDueThenTitle(_ lhs: WidgetTask, _ rhs: WidgetTask) -> Bool {
    let lhsOverdue = isOverdue(lhs)
    let rhsOverdue = isOverdue(rhs)
    if lhsOverdue != rhsOverdue {
      return lhsOverdue
    }
    let dateA = parseTaskDate(lhs)
    let dateB = parseTaskDate(rhs)
    if dateA == nil && dateB == nil {
      return lhs.title.lowercased() < rhs.title.lowercased()
    }
    if dateA == nil {
      return false
    }
    if dateB == nil {
      return true
    }
    if let dateA, let dateB, dateA != dateB {
      return dateA < dateB
    }
    return lhs.title.lowercased() < rhs.title.lowercased()
  }

  private static func startOfDay(_ date: Date) -> Date {
    Calendar.current.startOfDay(for: date)
  }

  private static func dayDiff(from start: Date, to end: Date) -> Int {
    Int(floor((startOfDay(end).timeIntervalSince(startOfDay(start))) / msPerDay))
  }
}
