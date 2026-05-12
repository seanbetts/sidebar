import Foundation
import sideBarShared

struct EmptyStateContent: Equatable {
    let title: String
    let subtitle: String?
    let icon: AppIcon?

    var systemImage: String? {
        icon?.rawValue
    }

    init(title: String, subtitle: String? = nil, icon: AppIcon? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
    }

    init(title: String, subtitle: String? = nil, systemImage: String) {
        self.init(title: title, subtitle: subtitle, icon: AppIcon(rawValue: systemImage))
    }

    static func noContentYet(
        title: String,
        subtitle: String? = nil,
        icon: AppIcon? = nil
    ) -> EmptyStateContent {
        EmptyStateContent(title: title, subtitle: subtitle, icon: icon)
    }

    static func noContentYet(
        title: String,
        subtitle: String? = nil,
        systemImage: String
    ) -> EmptyStateContent {
        EmptyStateContent(title: title, subtitle: subtitle, systemImage: systemImage)
    }

    static func noResults(subtitle: String? = nil) -> EmptyStateContent {
        EmptyStateContent(
            title: "No results",
            subtitle: subtitle,
            icon: AppIcon.Action.search
        )
    }

    static func noSelection(
        title: String,
        subtitle: String? = nil,
        icon: AppIcon? = nil
    ) -> EmptyStateContent {
        EmptyStateContent(title: title, subtitle: subtitle, icon: icon)
    }

    static func noSelection(
        title: String,
        subtitle: String? = nil,
        systemImage: String
    ) -> EmptyStateContent {
        EmptyStateContent(title: title, subtitle: subtitle, systemImage: systemImage)
    }

    static func allTasksCompleted(subtitle: String? = nil) -> EmptyStateContent {
        EmptyStateContent(
            title: "All tasks completed",
            subtitle: subtitle,
            icon: AppIcon.State.successCircle
        )
    }
}
