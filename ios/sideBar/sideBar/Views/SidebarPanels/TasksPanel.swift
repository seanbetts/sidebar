import SwiftUI

public struct TasksPanel: View {
    @EnvironmentObject private var environment: AppEnvironment

    public init() {
    }

    public var body: some View {
        TasksPanelView(viewModel: environment.tasksViewModel)
    }
}

struct TasksPanelView: View {
    static let actionControlChromeStyle: HeaderActionControlChromeStyle = .glass

    @ObservedObject var viewModel: TasksViewModel
    @EnvironmentObject var environment: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif
    @State private var hasLoaded = false
    @State var showNewGroupAlert: Bool = false
    @State var showNewProjectAlert: Bool = false
    @State private var showProjectGroupDialog: Bool = false
    @State private var newGroupTitle: String = ""
    @State private var newProjectTitle: String = ""
    @State private var pendingProjectTitle: String = ""
    @State private var renameTarget: TaskListTarget?
    @State private var renameValue: String = ""
    @State private var deleteTarget: TaskListTarget?
    @FocusState private var isSearchFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .sidebarPanelScaffoldBackground()
        .frame(maxHeight: .infinity)
        .onAppear {
            if !hasLoaded {
                hasLoaded = true
                Task { await viewModel.load(selection: viewModel.preferredLoadSelection) }
                Task { await viewModel.loadCounts() }
            }
        }
        .onChange(of: viewModel.selection) { _, newValue in
            if case .search = newValue {
                return
            }
            if !viewModel.searchQuery.isEmpty {
                viewModel.clearSearchQuery()
            }
        }
        .onReceive(environment.navigation.$shortcutActionEvent) { event in
            guard let event, event.section == .tasks else { return }
            switch event.action {
            case .focusSearch:
                isSearchFocused = true
            case .newItem:
                handleNewTaskTap()
            case .createTaskGroup:
                showNewGroupAlert = true
            case .createTaskProject:
                showNewProjectAlert = true
            default:
                break
            }
        }
        .alert("New group", isPresented: $showNewGroupAlert) {
            TextField("Group name", text: $newGroupTitle)
            Button("Cancel", role: .cancel) { newGroupTitle = "" }
            Button("Save") { handleCreateGroup() }
        } message: {
            Text("Add a new group for your tasks.")
        }
        .alert("New project", isPresented: $showNewProjectAlert) {
            TextField("Project name", text: $newProjectTitle)
            Button("Cancel", role: .cancel) { newProjectTitle = "" }
            Button("Next") { handleProjectTitleNext() }
        } message: {
            Text("Name your project, then pick a group.")
        }
        .alert(renameAlertTitle, isPresented: renameAlertBinding) {
            TextField(renamePlaceholder, text: $renameValue)
            Button("Cancel", role: .cancel) { clearRenameState() }
            Button("Save") { handleRenameTarget() }
        } message: {
            Text(renameAlertMessage)
        }
        .deleteConfirmationAlert(
            title: deleteAlertTitle,
            isPresented: deleteAlertBinding,
            message: deleteAlertMessage,
            onConfirm: handleDeleteTarget,
            onCancel: clearDeleteState
        )
        .confirmationDialog("Choose group", isPresented: $showProjectGroupDialog, titleVisibility: .visible) {
            Button("No group") { handleCreateProject(groupId: nil) }
            let sortedGroups = viewModel.groups.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            ForEach(sortedGroups, id: \.id) { group in
                Button(group.title) { handleCreateProject(groupId: group.id) }
            }
            Button("Cancel", role: .cancel) {
                showProjectGroupDialog = false
            }
        }
    }
}

extension TasksPanelView {
    private var header: some View {
        let showsInlineSearch = ContentView.shouldShowCompactPhoneInlineSearch(
            isCompact: isCompact,
            isPhoneIdiom: isCompactPhone
        )

        return VStack(spacing: DesignTokens.Spacing.sm) {
            PanelHeader(title: "Tasks") {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    if !isCompactPhone {
                        addMenuButton
                    }
                    if isCompact {
                        GlobalAvatarRegionControls()
                    }
                }
            }
            if showsInlineSearch {
                SearchField(
                    text: Binding(
                        get: { viewModel.searchQuery },
                        set: { viewModel.updateSearch(query: $0) }
                    ),
                    placeholder: "Search tasks",
                    isFocused: $isSearchFocused
                )
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.bottom, DesignTokens.Spacing.sm)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: LayoutMetrics.searchablePanelHeaderMinHeight(showsInlineSearch: showsInlineSearch),
            alignment: .top
        )
        .sidebarPanelHeaderBackground(showsInlineSearch: showsInlineSearch)
    }

    @ViewBuilder
    private var content: some View {
        tasksPanelList {
            Section {
                tasksListRow(
                    title: "Today",
                    iconName: "calendar",
                    count: viewModel.counts?.counts.today,
                    selection: .today
                )
                tasksListRow(
                    title: "Upcoming",
                    iconName: "calendar.badge.clock",
                    count: upcomingCount,
                    selection: .upcoming
                )
                tasksListRow(
                    title: "Completed",
                    iconName: "calendar.badge.checkmark",
                    count: viewModel.counts?.counts.completed,
                    selection: .completed
                )
            }

            if !groupsSorted.isEmpty {
                Section {
                    ForEach(groupsSorted, id: \.id) { group in
                        tasksListRow(
                            title: group.title,
                            iconName: "square.3.layers.3d",
                            count: groupCounts[group.id],
                            selection: .group(id: group.id),
                            onRename: { promptRename(group: group) },
                            onDelete: { promptDelete(group: group) }
                        )
                        let projects = projectsByGroup[group.id] ?? []
                        ForEach(projects, id: \.id) { project in
                            tasksListRow(
                                title: project.title,
                                iconName: "list.bullet",
                                count: projectCounts[project.id],
                                selection: .project(id: project.id),
                                indent: 18,
                                onRename: { promptRename(project: project) },
                                onDelete: { promptDelete(project: project) }
                            )
                        }
                    }
                }
            }

            if !orphanProjects.isEmpty {
                Section {
                    ForEach(orphanProjects, id: \.id) { project in
                        tasksListRow(
                            title: project.title,
                            iconName: "list.bullet",
                            count: projectCounts[project.id],
                            selection: .project(id: project.id),
                            onRename: { promptRename(project: project) },
                            onDelete: { promptDelete(project: project) }
                        )
                    }
                } header: {
                    sidebarSectionHeader("Projects")
                }
            }
        }
        .sidebarPanelListStyle()
        .sidebarCompactPhoneTopPadding(
            LayoutMetrics.compactPhoneTasksPanelTopPadding,
            isCompactPhone: isCompactPhone
        )
        .scrollContentBackground(.hidden)
        .sidebarPanelListBackground()
        .refreshable {
            await viewModel.load(selection: viewModel.preferredLoadSelection, force: true)
            await viewModel.loadCounts(force: true)
        }
    }

    @ViewBuilder
    private func tasksListRow(
        title: String,
        iconName: String,
        count: Int?,
        selection: TaskSelection,
        indent: CGFloat = 0,
        onRename: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) -> some View {
        TaskPanelRow(
            title: title,
            iconName: iconName,
            count: count,
            isSelected: isCompact ? false : viewModel.selection == selection,
            indent: indent,
            primaryAction: {
                let isAlreadySelected = viewModel.selection == selection
                if isCompact {
                    environment.tasksPhoneDetailRouteId = selection.cacheKey
                }
                environment.commandSelection = .tasks
                guard !isAlreadySelected else { return }
                Task { await viewModel.load(selection: selection) }
            },
            onRename: onRename,
            onDelete: onDelete
        )
    }

    func activateTaskSelection(_ selection: TaskSelection) {
        environment.commandSelection = .tasks
        Task { await viewModel.load(selection: selection) }
    }
}

private extension TasksPanelView {
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

    func promptRename(group: TaskGroup) {
        renameTarget = TaskListTarget(id: group.id, title: group.title, kind: .group)
        renameValue = group.title
    }

    func promptRename(project: TaskProject) {
        renameTarget = TaskListTarget(id: project.id, title: project.title, kind: .project)
        renameValue = project.title
    }

    func promptDelete(group: TaskGroup) {
        deleteTarget = TaskListTarget(id: group.id, title: group.title, kind: .group)
    }

    func promptDelete(project: TaskProject) {
        deleteTarget = TaskListTarget(id: project.id, title: project.title, kind: .project)
    }

    func handleRenameTarget() {
        guard let target = renameTarget else { return }
        let title = renameValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            clearRenameState()
            return
        }
        Task {
            do {
                switch target.kind {
                case .group:
                    try await viewModel.renameGroup(groupId: target.id, title: title)
                case .project:
                    try await viewModel.renameProject(projectId: target.id, title: title)
                }
                clearRenameState()
            } catch {
                viewModel.setErrorMessage(ErrorMapping.message(for: error))
            }
        }
    }

    func handleDeleteTarget() {
        guard let target = deleteTarget else { return }
        Task {
            do {
                switch target.kind {
                case .group:
                    try await viewModel.deleteGroup(groupId: target.id)
                case .project:
                    try await viewModel.deleteProject(projectId: target.id)
                }
                clearDeleteState()
            } catch {
                viewModel.setErrorMessage(ErrorMapping.message(for: error))
            }
        }
    }

    func clearRenameState() {
        renameTarget = nil
        renameValue = ""
    }

    func clearDeleteState() {
        deleteTarget = nil
    }

    var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { isPresented in
                if !isPresented {
                    clearRenameState()
                }
            }
        )
    }

    var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { isPresented in
                if !isPresented {
                    clearDeleteState()
                }
            }
        )
    }

    var renameAlertTitle: String {
        switch renameTarget?.kind {
        case .group:
            return "Rename group"
        case .project:
            return "Rename project"
        case .none:
            return "Rename"
        }
    }

    var renameAlertMessage: String {
        switch renameTarget?.kind {
        case .group:
            return "Update the group name."
        case .project:
            return "Update the project name."
        case .none:
            return ""
        }
    }

    var renamePlaceholder: String {
        switch renameTarget?.kind {
        case .group:
            return "Group name"
        case .project:
            return "Project name"
        case .none:
            return "Name"
        }
    }

    var deleteAlertTitle: String {
        switch deleteTarget?.kind {
        case .group:
            return "Delete group"
        case .project:
            return "Delete project"
        case .none:
            return "Delete"
        }
    }

    var deleteAlertMessage: String {
        switch deleteTarget?.kind {
        case .group:
            return "This will delete the group, all nested projects, and all tasks in those lists. This action cannot be undone."
        case .project:
            return "This will delete the project and all tasks in it. This action cannot be undone."
        case .none:
            return ""
        }
    }
}
