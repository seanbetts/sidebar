import SwiftUI
#if os(iOS)
import UIKit
#endif

extension TasksPanelView {
    @ViewBuilder
    func tasksPanelList<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        sidebarPanelList(selection: taskSelectionBinding) {
            content()
        }
    }

    var groupsSorted: [TaskGroup] {
        viewModel.panelGroupsSorted
    }

    /// Use filtered count for Upcoming (excludes undated tasks).
    /// When Upcoming is selected, use the live viewState count.
    /// Otherwise, use the cached filtered count from the last Upcoming load.
    var upcomingCount: Int? {
        if case .upcoming = viewModel.selection {
            return viewModel.viewState.totalCount
        }
        // Use cached filtered count if available, otherwise fall back to server count
        return viewModel.filteredUpcomingCount ?? viewModel.counts?.counts.upcoming
    }

    var projectsByGroup: [String: [TaskProject]] {
        viewModel.panelProjectsByGroup
    }

    var orphanProjects: [TaskProject] {
        viewModel.panelOrphanProjects
    }

    var groupCounts: [String: Int] {
        viewModel.panelGroupCounts
    }

    var projectCounts: [String: Int] {
        viewModel.panelProjectCounts
    }

    var panelBackground: Color {
        PlatformTokens.sidebarPanelBackground
    }

    var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    var isCompactPhone: Bool {
        isCompact && isPhone
    }

    var taskSelectionBinding: Binding<TaskSelection?> {
        Binding(
            get: { self.viewModel.selection },
            set: { newValue in
                guard let newValue, newValue != self.viewModel.selection else { return }
                self.activateTaskSelection(newValue)
            }
        )
    }

    private var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

}
