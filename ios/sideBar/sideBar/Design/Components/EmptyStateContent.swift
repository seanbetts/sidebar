import Foundation

struct EmptyStateContent: Equatable {
    let title: String
    let subtitle: String?
    let systemImage: String?

    static func noContentYet(
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil
    ) -> EmptyStateContent {
        EmptyStateContent(title: title, subtitle: subtitle, systemImage: systemImage)
    }

    static func noResults(subtitle: String? = nil) -> EmptyStateContent {
        EmptyStateContent(
            title: "No results",
            subtitle: subtitle,
            systemImage: "magnifyingglass"
        )
    }

    static func noSelection(
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil
    ) -> EmptyStateContent {
        EmptyStateContent(title: title, subtitle: subtitle, systemImage: systemImage)
    }

    static func allTasksCompleted(subtitle: String? = nil) -> EmptyStateContent {
        EmptyStateContent(
            title: "All tasks completed",
            subtitle: subtitle,
            systemImage: "checkmark.circle"
        )
    }
}
