import Foundation

extension TasksDetailView {
    static func emptyStateContent(
        for selection: TaskSelection,
        searchQuery: String?
    ) -> EmptyStateContent {
        switch selection {
        case .none:
            return .noSelection(
                title: "Select a list",
                subtitle: "Pick a task list from the sidebar to get started.",
                systemImage: "checkmark.circle"
            )
        case .search:
            let subtitle = (searchQuery ?? "").isEmpty
                ? "No results for your search."
                : "No results for \"\(searchQuery ?? "")\""
            return .noResults(subtitle: subtitle)
        case .today, .group, .project:
            return .allTasksCompleted()
        case .upcoming:
            return .noContentYet(
                title: "No upcoming tasks yet",
                systemImage: "calendar"
            )
        case .completed:
            return .noContentYet(
                title: "No completed tasks yet",
                systemImage: "checkmark.circle"
            )
        }
    }
}
