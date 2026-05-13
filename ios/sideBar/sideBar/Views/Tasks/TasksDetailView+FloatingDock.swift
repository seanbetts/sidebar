import SwiftUI
import sideBarShared
#if os(iOS)
import UIKit
#endif

extension TasksDetailView {
    static func shouldDisplayWorkspaceFloatingActionDock(
        isCompact: Bool,
        isPhoneIdiom: Bool,
        selection: TaskSelection
    ) -> Bool {
        guard !isCompact else { return false }
        guard isPhoneIdiom else { return false }
        return selection != .none
    }

    func shouldShowWorkspaceFloatingActionDock(for selection: TaskSelection) -> Bool {
        Self.shouldDisplayWorkspaceFloatingActionDock(
            isCompact: isCompact,
            isPhoneIdiom: isPhoneIdiom,
            selection: selection
        )
    }

    var workspaceFloatingActionDock: some View {
        PhoneFloatingActionDock {
            PhoneFloatingActionButton(
                systemName: AppIcon.Action.add.rawValue,
                accessibilityLabel: "New task"
            ) {
                viewModel.startNewTask()
            }
        }
        .accessibilityIdentifier("tasks-workspace-floating-dock")
    }

    private var isPhoneIdiom: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    func todaySectionSelection(for section: TaskSection, state: TasksViewState) -> TaskSelection? {
        if section.id.hasPrefix("project:") {
            let projectId = String(section.id.dropFirst("project:".count))
            return .project(id: projectId)
        }
        if state.groupTitleById[section.id] != nil {
            return .group(id: section.id)
        }
        if state.projectTitleById[section.id] != nil {
            return .project(id: section.id)
        }
        return nil
    }

    func taskMenu(for task: TaskItem, selection: TaskSelection) -> some View {
        Group {
            Button("Rename") { openRename(task) }
            Button("Edit notes") { openNotes(task) }
            Button("Move to...") { openMove(task) }
            Divider()
            Button(task.repeating == true ? "Edit repeat..." : "Repeat...") { openRepeat(task) }
            Divider()
            if !task.isPreview {
                if selection != .today {
                    Button("Set due today") { Task { await viewModel.setDueDate(task: task, date: Date()) } }
                }
                Button("Defer to tomorrow") { Task { await viewModel.deferTask(task: task, days: 1) } }
                Button("Defer to Friday") { Task { await viewModel.deferTask(task: task, days: nextWeekdayOffset(targetWeekday: 5)) } }
                Button("Defer to weekend") { Task { await viewModel.deferTask(task: task, days: nextWeekdayOffset(targetWeekday: 6)) } }
                Divider()
                Button("Set due date...") { openDue(task) }
                Button("Clear due date") { Task { await viewModel.clearDueDate(task: task) } }
                Divider()
            }
            Button("Delete", role: .destructive) { deleteTask = task }
        }
    }

    func tasksCountLabel(for state: TasksViewState) -> String? {
        if state.totalCount == 0 { return nil }
        if state.totalCount == 1 { return "1 task" }
        return "\(state.totalCount) tasks"
    }

    func openRename(_ task: TaskItem) {
        renameTask = task
        setActiveTask(task)
    }
}
