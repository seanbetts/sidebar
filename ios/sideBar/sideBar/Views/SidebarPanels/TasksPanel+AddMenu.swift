import SwiftUI
import sideBarShared

extension TasksPanelView {
    @ViewBuilder
    var addMenuButton: some View {
        #if os(macOS)
        HeaderActionMenuControl(
            icon: AppIcon.Action.add,
            accessibilityLabel: "Add",
            chromeStyle: Self.actionControlChromeStyle
        ) {
            addMenuItems
        }
        #else
        HeaderActionMenuButton(
            icon: AppIcon.Action.add,
            accessibilityLabel: "Add",
            items: addSidebarMenuItems,
            isCompact: isCompact,
            chromeStyle: Self.actionControlChromeStyle
        )
        #endif
    }

    @ViewBuilder
    var addMenuItems: some View {
        sidebarMenuItemsView(addSidebarMenuItems)
    }

    var addSidebarMenuItems: [SidebarMenuItem] {
        [
            .newTask {
                handleNewTaskTap()
            },
            .newGroup {
                showNewGroupAlert = true
            },
            .newProject {
                showNewProjectAlert = true
            }
        ]
    }

    func handleNewTaskTap() {
        if Self.shouldDeepLinkForCompactNewTask(
            isCompact: isCompact,
            tasksPhoneDetailRouteId: environment.tasksPhoneDetailRouteId
        ) {
            environment.commandSelection = .tasks
            environment.pendingSidebarDeepLink = URL(string: "sidebar://tasks/new")
            environment.tasksPhoneDetailRouteId = TaskSelection.today.cacheKey
        } else {
            viewModel.startNewTask()
        }
    }

    static func shouldDeepLinkForCompactNewTask(
        isCompact: Bool,
        tasksPhoneDetailRouteId: String?
    ) -> Bool {
        isCompact && tasksPhoneDetailRouteId == nil
    }
}
