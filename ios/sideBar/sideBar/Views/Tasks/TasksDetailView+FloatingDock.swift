import SwiftUI

extension TasksDetailView {
    static func shouldDisplayWorkspaceFloatingActionDock(
        isCompact: Bool,
        selection: TaskSelection
    ) -> Bool {
        guard !isCompact else { return false }
        return selection != .none
    }

    func shouldShowWorkspaceFloatingActionDock(for selection: TaskSelection) -> Bool {
        Self.shouldDisplayWorkspaceFloatingActionDock(isCompact: isCompact, selection: selection)
    }

    var workspaceFloatingActionDock: some View {
        PhoneFloatingActionDock {
            Menu {
                Button {
                    viewModel.startNewTask()
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
            } label: {
                Image(systemName: "plus")
                    .font(DesignTokens.Typography.labelMd)
                    .frame(
                        width: PhoneFloatingActionMetrics.buttonSize,
                        height: PhoneFloatingActionMetrics.buttonSize
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add")
        }
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

    func handleCreateGroup() {
        let title = newGroupTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        newGroupTitle = ""
        Task {
            do {
                try await viewModel.createGroup(title: title)
            } catch {
                viewModel.setErrorMessage(ErrorMapping.message(for: error))
            }
        }
    }

    func handleProjectTitleNext() {
        let title = newProjectTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        pendingProjectTitle = title
        newProjectTitle = ""
        if let preferredGroupId = preferredGroupIdForNewProject() {
            handleCreateProject(groupId: preferredGroupId)
            return
        }
        if viewModel.groups.isEmpty {
            handleCreateProject(groupId: nil)
            return
        }
        showProjectGroupDialog = true
    }

    func handleCreateProject(groupId: String?) {
        let title = pendingProjectTitle
        pendingProjectTitle = ""
        guard !title.isEmpty else { return }
        Task {
            do {
                try await viewModel.createProject(title: title, groupId: groupId)
            } catch {
                viewModel.setErrorMessage(ErrorMapping.message(for: error))
            }
        }
    }

    func preferredGroupIdForNewProject() -> String? {
        switch viewModel.selection {
        case .group(let id):
            return id
        case .project(let id):
            return viewModel.projects.first(where: { $0.id == id })?.groupId
        default:
            return nil
        }
    }
}
