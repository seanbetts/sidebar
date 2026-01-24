import SwiftUI

public struct TasksPanel: View {
    @EnvironmentObject private var environment: AppEnvironment

    public init() {
    }

    public var body: some View {
        TasksPanelView(viewModel: environment.tasksViewModel)
    }
}

private struct TasksPanelView: View {
    @ObservedObject var viewModel: TasksViewModel
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var searchQuery: String = ""
    @State private var hasLoaded = false
    @State private var showNewGroupAlert: Bool = false
    @State private var showNewProjectAlert: Bool = false
    @State private var showProjectGroupDialog: Bool = false
    @State private var newGroupTitle: String = ""
    @State private var newProjectTitle: String = ""
    @State private var pendingProjectTitle: String = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            if !hasLoaded {
                hasLoaded = true
                Task { await viewModel.load(selection: viewModel.selection) }
                Task { await viewModel.loadCounts() }
            }
            if searchQuery.isEmpty {
                searchQuery = viewModel.searchQuery
            }
        }
        .onChange(of: searchQuery) { _, newValue in
            viewModel.updateSearch(query: newValue)
        }
        .onChange(of: viewModel.searchQuery) { _, newValue in
            if searchQuery != newValue {
                searchQuery = newValue
            }
        }
        .onChange(of: viewModel.selection) { _, newValue in
            if case .search = newValue {
                return
            }
            if !searchQuery.isEmpty {
                searchQuery = ""
            }
        }
        .onReceive(environment.$shortcutActionEvent) { event in
            guard let event, event.section == .tasks else { return }
            switch event.action {
            case .focusSearch:
                isSearchFocused = true
            case .newItem:
                viewModel.startNewTask()
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
        .confirmationDialog("Choose group", isPresented: $showProjectGroupDialog, titleVisibility: .visible) {
            Button("No group") { handleCreateProject(groupId: nil) }
            ForEach(viewModel.groups.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }, id: \.id) { group in
                Button(group.title) { handleCreateProject(groupId: group.id) }
            }
        }
    }
}

extension TasksPanelView {
    private var header: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            PanelHeader(title: "Tasks") {
                HStack(spacing: DesignTokens.Spacing.xs) {
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
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add")
                    if isCompact {
                        SettingsAvatarButton()
                    }
                }
            }
            SearchField(text: $searchQuery, placeholder: "Search tasks", isFocused: $isSearchFocused)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.bottom, DesignTokens.Spacing.sm)
        }
        .frame(minHeight: LayoutMetrics.panelHeaderMinHeight)
        .background(panelHeaderBackground(colorScheme))
    }

    @ViewBuilder
    private var content: some View {
        if let error = viewModel.errorMessage {
            SidebarPanelPlaceholder(
                title: "Unable to load tasks",
                subtitle: error,
                actionTitle: "Retry"
            ) {
                Task { await viewModel.load(selection: viewModel.selection, force: true) }
            }
        } else {
            List {
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
                        count: viewModel.counts?.counts.upcoming,
                        selection: .upcoming
                    )
                }

                if !groupsSorted.isEmpty {
                    Section {
                        ForEach(groupsSorted, id: \.id) { group in
                            tasksListRow(
                                title: group.title,
                                iconName: "square.3.layers.3d",
                                count: groupCounts[group.id],
                                selection: .group(id: group.id)
                            )
                            let projects = projectsByGroup[group.id] ?? []
                            ForEach(projects, id: \.id) { project in
                                tasksListRow(
                                    title: project.title,
                                    iconName: "list.bullet",
                                    count: projectCounts[project.id],
                                    selection: .project(id: project.id),
                                    indent: 18
                                )
                            }
                        }
                    }
                }

                if !orphanProjects.isEmpty {
                    Section("Projects") {
                        ForEach(orphanProjects, id: \.id) { project in
                            tasksListRow(
                                title: project.title,
                                iconName: "list.bullet",
                                count: projectCounts[project.id],
                                selection: .project(id: project.id)
                            )
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(panelBackground)
            .refreshable {
                await viewModel.load(selection: viewModel.selection, force: true)
                await viewModel.loadCounts(force: true)
            }
        }
    }

    @ViewBuilder
    private func tasksListRow(
        title: String,
        iconName: String,
        count: Int?,
        selection: TaskSelection,
        indent: CGFloat = 0
    ) -> some View {
        TaskPanelRow(
            title: title,
            iconName: iconName,
            count: count,
            isSelected: viewModel.selection == selection,
            indent: indent
        )
        .onTapGesture {
            Task { await viewModel.load(selection: selection) }
        }
    }

    private var groupsSorted: [TaskGroup] {
        viewModel.groups.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var projectsByGroup: [String: [TaskProject]] {
        var map: [String: [TaskProject]] = [:]
        for project in viewModel.projects.sorted(by: { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) {
            if let groupId = project.groupId {
                map[groupId, default: []].append(project)
            }
        }
        return map
    }

    private var orphanProjects: [TaskProject] {
        viewModel.projects.filter { $0.groupId == nil }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var groupCounts: [String: Int] {
        var counts = Dictionary(uniqueKeysWithValues: (viewModel.counts?.groups ?? []).map { ($0.id, $0.count) })
        viewModel.groups.forEach { group in
            if counts[group.id] == nil {
                counts[group.id] = 0
            }
        }
        return counts
    }

    private var projectCounts: [String: Int] {
        var counts = Dictionary(uniqueKeysWithValues: (viewModel.counts?.projects ?? []).map { ($0.id, $0.count) })
        viewModel.projects.forEach { project in
            if counts[project.id] == nil {
                counts[project.id] = 0
            }
        }
        return counts
    }

    private var panelBackground: Color {
        DesignTokens.Colors.sidebar
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
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
}
