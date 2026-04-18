import Foundation
import WidgetKit
import sideBarShared

// MARK: - Widget Task Ordering

private let widgetTasksDateFormatter: DateFormatter = {
  let formatter = DateFormatter()
  formatter.dateFormat = "yyyy-MM-dd"
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = TimeZone.current
  return formatter
}()

public enum WidgetTasksUtils {
  private static let secondsPerDay: Double = 24 * 60 * 60
  private static let completionDisplayDurationSeconds: TimeInterval = 1.25

  public static func visibleTasks(_ tasks: [WidgetTask], now: Date) -> [WidgetTask] {
    tasks.filter { task in
      !hasCompletionDisplayExpired(task, now: now)
    }
  }

  public static func completionRemovalDate(for task: WidgetTask) -> Date? {
    guard task.isCompleted, let completedAt = task.completedAt else { return nil }
    return completedAt.addingTimeInterval(completionDisplayDurationSeconds)
  }

  public static func hasCompletionDisplayExpired(_ task: WidgetTask, now: Date) -> Bool {
    guard let removalDate = completionRemovalDate(for: task) else { return false }
    return now >= removalDate
  }

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
    Int(floor((startOfDay(end).timeIntervalSince(startOfDay(start))) / secondsPerDay))
  }
}

enum WidgetGalleryPreviewContent {
  static func tasks(for family: WidgetFamily, now: Date = Date()) -> WidgetTaskData {
    let allTasks = [
      WidgetTask(
        id: "preview-task-1",
        title: "Review widget QA notes",
        projectName: "sideBar",
        deadline: taskDate(daysFromNow: 0, now: now)
      ),
      WidgetTask(
        id: "preview-task-2",
        title: "Confirm lock screen copy",
        projectName: "Design",
        hasNotes: true,
        deadline: taskDate(daysFromNow: 1, now: now)
      ),
      WidgetTask(
        id: "preview-task-3",
        title: "Send roadmap follow-up",
        groupName: "Ops",
        deadline: taskDate(daysFromNow: 2, now: now)
      ),
      WidgetTask(
        id: "preview-task-4",
        title: "Book train tickets",
        groupName: "Personal",
        deadline: taskDate(daysFromNow: 3, now: now)
      ),
      WidgetTask(
        id: "preview-task-5",
        title: "Prep weekly plan",
        projectName: "Planning",
        deadline: taskDate(daysFromNow: 4, now: now)
      ),
      WidgetTask(
        id: "preview-task-6",
        title: "Clear inbox triage",
        groupName: "Admin"
      )
    ]

    return WidgetTaskData(
      tasks: Array(allTasks.prefix(taskCount(for: family))),
      totalCount: allTasks.count,
      progressCompletedCount: 2,
      progressTotalCount: 8,
      lastUpdated: now
    )
  }

  static func allNotes(now: Date = Date()) -> WidgetNoteData {
    let allNotes = [
      WidgetNote(
        id: "preview-note-1",
        name: "Weekly planning",
        contentPreview: "Milestones, blockers, and owners",
        path: "/notes/weekly-planning",
        pinned: true,
        pinnedOrder: 0
      ),
      WidgetNote(
        id: "preview-note-2",
        name: "Product ideas",
        contentPreview: "StandBy widget concepts and follow-ups",
        path: "/notes/product-ideas",
        pinned: true,
        pinnedOrder: 1
      ),
      WidgetNote(
        id: "preview-note-3",
        name: "Launch checklist",
        contentPreview: "QA, docs, and release notes",
        path: "/notes/launch-checklist",
        pinned: true,
        pinnedOrder: 2
      ),
      WidgetNote(
        id: "preview-note-4",
        name: "Research clips",
        contentPreview: "WidgetKit and HIG references",
        path: "/notes/research-clips",
        pinned: true,
        pinnedOrder: 3
      ),
      WidgetNote(
        id: "preview-note-5",
        name: "Customer feedback",
        contentPreview: "Saved comments from last week",
        path: "/notes/customer-feedback",
        pinned: true,
        pinnedOrder: 4
      ),
      WidgetNote(
        id: "preview-note-6",
        name: "Retro actions",
        contentPreview: "Short list of follow-ups",
        path: "/notes/retro-actions",
        pinned: true,
        pinnedOrder: 5
      )
    ]

    return WidgetNoteData(notes: allNotes, totalCount: allNotes.count, lastUpdated: now)
  }

  static func notes(for family: WidgetFamily, now: Date = Date()) -> WidgetNoteData {
    let allNotes = allNotes(now: now)
    return WidgetNoteData(
      notes: Array(allNotes.notes.prefix(listCount(for: family))),
      totalCount: allNotes.totalCount,
      lastUpdated: allNotes.lastUpdated
    )
  }

  static func websites(for family: WidgetFamily, now: Date = Date()) -> WidgetWebsiteData {
    let allSites = [
      WidgetWebsite(id: "preview-site-1", title: "Linear changelog", url: "https://linear.app/changelog", domain: "linear.app"),
      WidgetWebsite(id: "preview-site-2", title: "Apple Developer", url: "https://developer.apple.com", domain: "developer.apple.com"),
      WidgetWebsite(id: "preview-site-3", title: "Supabase docs", url: "https://supabase.com/docs", domain: "supabase.com"),
      WidgetWebsite(id: "preview-site-4", title: "GitHub issues", url: "https://github.com/issues", domain: "github.com"),
      WidgetWebsite(id: "preview-site-5", title: "Figma board", url: "https://figma.com/files", domain: "figma.com"),
      WidgetWebsite(id: "preview-site-6", title: "Stripe changelog", url: "https://stripe.com/changelog", domain: "stripe.com")
    ]

    return WidgetWebsiteData(
      websites: Array(allSites.prefix(listCount(for: family))),
      totalCount: allSites.count,
      lastUpdated: now
    )
  }

  static func files(for family: WidgetFamily, now: Date = Date()) -> WidgetFileData {
    let allFiles = [
      WidgetFile(
        id: "preview-file-1",
        filename: "Design-System-Checklist.pdf",
        sizeBytes: 1_824_000,
        pinned: true,
        category: "reports",
        recommendedViewer: "viewer_pdf"
      ),
      WidgetFile(
        id: "preview-file-2",
        filename: "Roadmap-Notes.md",
        sizeBytes: 12_400,
        pinned: true,
        category: "documents",
        recommendedViewer: "ai_md"
      ),
      WidgetFile(
        id: "preview-file-3",
        filename: "Widget-Review.mov",
        sizeBytes: 22_500_000,
        pinned: true,
        category: "video",
        recommendedViewer: "viewer_video"
      ),
      WidgetFile(
        id: "preview-file-4",
        filename: "Metrics.json",
        sizeBytes: 2_800,
        pinned: true,
        category: "other",
        recommendedViewer: "viewer_json"
      ),
      WidgetFile(
        id: "preview-file-5",
        filename: "Sprint-Deck.key",
        sizeBytes: 4_300_000,
        pinned: true,
        category: "presentations",
        recommendedViewer: "viewer_presentation"
      ),
      WidgetFile(
        id: "preview-file-6",
        filename: "Voice-Notes.m4a",
        sizeBytes: 680_000,
        pinned: true,
        category: "audio",
        recommendedViewer: "audio_original"
      )
    ]

    return WidgetFileData(
      files: Array(allFiles.prefix(listCount(for: family))),
      totalCount: allFiles.count,
      lastUpdated: now
    )
  }

  private static func taskCount(for family: WidgetFamily) -> Int {
    switch family {
    case .accessoryRectangular:
      return 2
    case .systemLarge:
      return 5
    default:
      return 3
    }
  }

  private static func listCount(for family: WidgetFamily) -> Int {
    switch family {
    case .systemLarge:
      return 5
    default:
      return 3
    }
  }

  private static func taskDate(daysFromNow: Int, now: Date) -> String {
    let date = Calendar.current.date(byAdding: .day, value: daysFromNow, to: now) ?? now
    return widgetTasksDateFormatter.string(from: date)
  }
}
