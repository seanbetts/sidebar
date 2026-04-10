import SwiftUI

extension TasksPanelView {
    @ViewBuilder
    var addMenuButton: some View {
        #if os(macOS)
        HeaderActionMenuControl(
            systemName: "plus",
            accessibilityLabel: "Add",
            chromeStyle: Self.actionControlChromeStyle
        ) {
            addMenuItems
        }
        #else
        HeaderActionMenuButton(
            systemImage: "plus",
            accessibilityLabel: "Add",
            items: addSidebarMenuItems,
            isCompact: isCompact,
            chromeStyle: Self.actionControlChromeStyle
        )
        #endif
    }

    @ViewBuilder
    var addMenuItems: some View {
        Button {
            handleNewTaskTap()
        } label: {
            Label("New task", systemImage: "checkmark.circle")
        }
        Button {
            showNewGroupAlert = true
        } label: {
            Label("New group", systemImage: "folder")
        }
        Button {
            showNewProjectAlert = true
        } label: {
            Label("New project", systemImage: "list.bullet.rectangle")
        }
    }

    var addSidebarMenuItems: [SidebarMenuItem] {
        [
            SidebarMenuItem(title: "New task", systemImage: "checkmark.circle", role: nil) {
                handleNewTaskTap()
            },
            SidebarMenuItem(title: "New group", systemImage: "folder", role: nil) {
                showNewGroupAlert = true
            },
            SidebarMenuItem(title: "New project", systemImage: "list.bullet.rectangle", role: nil) {
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
            environment.pendingNewTaskDeepLink = true
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
