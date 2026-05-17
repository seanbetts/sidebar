import Foundation
import sideBarShared

struct WidgetEmptyStateContent: Equatable {
    let title: String
    let subtitle: String?
    let appIcon: AppIcon
    let lockScreenLabel: String

    static func allTasksCompleted(
        subtitle: String,
        appIcon: AppIcon
    ) -> WidgetEmptyStateContent {
        WidgetEmptyStateContent(
            title: "All tasks completed",
            subtitle: subtitle,
            appIcon: appIcon,
            lockScreenLabel: "All tasks completed"
        )
    }

    static func noPinnedNotes() -> WidgetEmptyStateContent {
        WidgetEmptyStateContent(
            title: "No pinned notes",
            subtitle: "Pin a note to see it here",
            appIcon: AppIcon.Action.pin,
            lockScreenLabel: "No pinned notes"
        )
    }

    static func noNotes(in title: String) -> WidgetEmptyStateContent {
        WidgetEmptyStateContent(
            title: "No notes in \(title)",
            subtitle: "This folder is empty",
            appIcon: AppIcon.Content.folder,
            lockScreenLabel: "No notes"
        )
    }

    static func noPinnedFiles() -> WidgetEmptyStateContent {
        WidgetEmptyStateContent(
            title: "No pinned files",
            subtitle: "Pin a file to see it here",
            appIcon: AppIcon.Action.pin,
            lockScreenLabel: "No pinned files"
        )
    }

    static func noSavedWebsites() -> WidgetEmptyStateContent {
        WidgetEmptyStateContent(
            title: "No saved websites",
            subtitle: "Save a website to see it here",
            appIcon: AppIcon.Domain.websites,
            lockScreenLabel: "No saved websites"
        )
    }
}
