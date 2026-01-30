import Foundation

// MARK: - Widget Content Type

/// Identifies content types for widget storage with associated keys and widget kinds
public enum WidgetContentType: String, CaseIterable {
  case tasks
  case notes
  case websites
  case files

  /// UserDefaults key for the main data snapshot
  public var dataKey: String {
    "widget_\(rawValue)_data"
  }

  /// UserDefaults key for pending operations
  public var pendingKey: String {
    "widget_\(rawValue)_pending"
  }

  /// Widget kinds associated with this content type for targeted reloads
  public var widgetKinds: [String] {
    switch self {
    case .tasks:
      return [
        "TodayTasksWidget",
        "TaskCountWidget",
        "LockScreenTaskCountWidget",
        "LockScreenTaskPreviewWidget",
        "LockScreenInlineWidget"
      ]
    case .notes:
      return [
        "PinnedNotesWidget",
        "LockScreenNoteCount",
        "LockScreenNotePreview",
        "LockScreenNotesInline"
      ]
    case .websites:
      return [
        "PinnedSitesWidget",
        "LockScreenSiteCount",
        "LockScreenSitePreview",
        "LockScreenSitesInline"
      ]
    case .files:
      return [
        "RecentFilesWidget",
        "PinnedFilesWidget"
      ]
    }
  }
}
