import Foundation

struct WidgetEmptyStateContent: Equatable {
    let title: String
    let subtitle: String?
    let systemImage: String
    let lockScreenLabel: String

    static func allTasksCompleted(
        subtitle: String,
        systemImage: String
    ) -> WidgetEmptyStateContent {
        WidgetEmptyStateContent(
            title: "All tasks completed",
            subtitle: subtitle,
            systemImage: systemImage,
            lockScreenLabel: "All tasks completed"
        )
    }

    static func noPinnedNotes() -> WidgetEmptyStateContent {
        WidgetEmptyStateContent(
            title: "No pinned notes",
            subtitle: "Pin a note to see it here",
            systemImage: "pin",
            lockScreenLabel: "No pinned notes"
        )
    }

    static func noNotes(in title: String) -> WidgetEmptyStateContent {
        WidgetEmptyStateContent(
            title: "No notes in \(title)",
            subtitle: "This folder is empty",
            systemImage: "folder",
            lockScreenLabel: "No notes"
        )
    }

    static func noPinnedFiles() -> WidgetEmptyStateContent {
        WidgetEmptyStateContent(
            title: "No pinned files",
            subtitle: "Pin a file to see it here",
            systemImage: "pin",
            lockScreenLabel: "No pinned files"
        )
    }

    static func noSavedWebsites() -> WidgetEmptyStateContent {
        WidgetEmptyStateContent(
            title: "No saved websites",
            subtitle: "Save a website to see it here",
            systemImage: "globe",
            lockScreenLabel: "No saved websites"
        )
    }
}
