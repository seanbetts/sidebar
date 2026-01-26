import SwiftUI

public struct TasksView: View {
    @EnvironmentObject private var environment: AppEnvironment
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.scenePhase) private var scenePhase

    public init() {
    }

    public var body: some View {
        TasksDetailView(viewModel: environment.tasksViewModel)
            .task {
                await environment.tasksViewModel.load(selection: environment.tasksViewModel.selection)
                await environment.tasksViewModel.loadCounts()
            }
            #if os(iOS)
            .onAppear {
                environment.isTasksFocused = true
                if environment.pendingNewTaskDeepLink {
                    environment.pendingNewTaskDeepLink = false
                    environment.tasksViewModel.startNewTask()
                }
            }
            .onDisappear {
                environment.isTasksFocused = false
            }
            .onChange(of: scenePhase) {
                guard scenePhase == .active else { return }
                Task {
                    await environment.tasksViewModel.load(selection: environment.tasksViewModel.selection, force: true)
                    await environment.tasksViewModel.loadCounts(force: true)
                }
            }
            #endif
            #if !os(macOS)
            .navigationTitle("Tasks")
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }
}

struct TasksDetailView: View {
    @ObservedObject var viewModel: TasksViewModel
    @EnvironmentObject private var environment: AppEnvironment
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif

    @State var renameTask: TaskItem?
    @State var renameValue: String = ""
    @State var notesTask: TaskItem?
    @State var dueTask: TaskItem?
    @State var dueDate: Date = Date()
    @State var moveTask: TaskItem?
    @State var selectedListId: String = ""
    @State var repeatTask: TaskItem?
    @State var repeatType: RepeatType = .daily
    @State var repeatInterval: Int = 1
    @State var repeatStartDate: Date = Date()
    @State var deleteTask: TaskItem?
    @State var activeTaskId: String?
    @State private var expandedTaskIds: Set<String> = []

    var body: some View {
        let state = viewModel.viewState
        VStack(spacing: 0) {
            if environment.isOffline {
                OfflineBanner()
            }
            if !isCompact {
                header(state: state)
                Divider()
            }
            content(state: state)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .alert("Rename task", isPresented: isRenamePresented) {
            TextField("Title", text: $renameValue)
                .submitLabel(.done)
                .onSubmit { commitRename() }
            Button("Rename") { commitRename() }
                .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { renameTask = nil }
        }
        .alert("Delete task", isPresented: isDeletePresented) {
            Button("Delete", role: .destructive) {
                guard let task = deleteTask else { return }
                Task { await viewModel.deleteTask(task: task) }
                deleteTask = nil
            }
            Button("Cancel", role: .cancel) { deleteTask = nil }
        } message: {
            Text("This will delete the task and any repeat instances.")
        }
        .sheet(item: $notesTask) { task in
            NotesSheet(
                task: task,
                notes: task.notes ?? "",
                onSave: { value in
                    Task { await viewModel.updateNotes(task: task, notes: value) }
                },
                onDismiss: { notesTask = nil }
            )
        }
        .sheet(item: $dueTask) { task in
            DueDateSheet(
                task: task,
                dueDate: dueDate,
                onSave: { date in
                    Task { await viewModel.setDueDate(task: task, date: date) }
                },
                onClear: {
                    Task { await viewModel.clearDueDate(task: task) }
                },
                onDismiss: { dueTask = nil }
            )
        }
        .sheet(item: $moveTask) { task in
            MoveTaskSheet(
                task: task,
                selectedListId: selectedListId,
                groups: viewModel.groups,
                projects: viewModel.projects,
                onSave: { listId in
                    Task { await viewModel.moveTask(task: task, listId: listId) }
                },
                onDismiss: { moveTask = nil }
            )
        }
        .sheet(item: $repeatTask) { task in
            RepeatTaskSheet(
                task: task,
                repeatType: repeatType,
                interval: repeatInterval,
                startDate: repeatStartDate,
                onSave: { type, interval, startDate in
                    let rule = buildRecurrenceRule(type: type, interval: interval, startDate: startDate)
                    Task { await viewModel.setRepeat(task: task, rule: rule, startDate: startDate) }
                },
                onDismiss: { repeatTask = nil }
            )
        }
        .sheet(isPresented: isNewTaskPresented) {
            if let draft = viewModel.newTaskDraft {
                NewTaskSheet(
                    draft: draft,
                    groups: viewModel.groups,
                    projects: viewModel.projects,
                    isSaving: viewModel.newTaskSaving,
                    errorMessage: viewModel.newTaskError,
                    onSave: { title, notes, dueDate, listId in
                        Task { await viewModel.createTask(title: title, notes: notes, dueDate: dueDate, listId: listId) }
                    },
                    onDismiss: { viewModel.cancelNewTask() }
                )
            }
        }
        .onReceive(environment.$shortcutActionEvent) { event in
            guard let event, event.section == .tasks else { return }
            guard let task = activeTask(in: state) else { return }
            switch event.action {
            case .completeTask:
                Task { await viewModel.completeTask(task: task) }
            case .editTaskNotes:
                openNotes(task)
            case .moveTask:
                openMove(task)
            case .setTaskDueDate:
                openDue(task)
            case .setTaskRepeat:
                openRepeat(task)
            case .deleteItem:
                deleteTask = task
            default:
                break
            }
        }
    }
}

extension TasksDetailView {
    private func header(state: TasksViewState) -> some View {
        ContentHeaderRow(
            iconName: state.titleIcon,
            title: state.selectionLabel,
            subtitle: nil,
            titleLineLimit: 1,
            subtitleLineLimit: 1,
            titleLayoutPriority: 1,
            subtitleLayoutPriority: 0
        ) {
            if state.totalCount == 0 {
                Image(systemName: "checkmark")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .accessibilityLabel("No tasks")
            } else if let label = tasksCountLabel(for: state) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .frame(height: LayoutMetrics.contentHeaderMinHeight)
    }

    @ViewBuilder
    private func content(state: TasksViewState) -> some View {
        if viewModel.isLoading || (isSearchSelection(state.selection) && viewModel.searchPending) {
            LoadingView(message: isSearchSelection(state.selection) ? "Loading search results..." : "Loading tasks...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage {
            PlaceholderView(
                title: "Unable to load tasks",
                subtitle: error,
                actionTitle: "Retry"
            ) {
                Task { await viewModel.load(selection: viewModel.selection, force: true) }
            }
        } else if state.sections.isEmpty {
            PlaceholderView(
                title: state.selectionLabel == "Today" ? "All done for the day" : "No tasks to show.",
                subtitle: searchSubtitle(selection: state.selection),
                iconName: "checkmark.circle"
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    ForEach(state.sections) { section in
                        if !section.title.isEmpty {
                            if case .today = state.selection {
                                todaySectionHeader(section: section, state: state)
                                    .padding(.horizontal, DesignTokens.Spacing.md)
                            } else {
                                Text(section.title)
                                    .font(.caption)
                                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                                    .padding(.horizontal, DesignTokens.Spacing.md)
                            }
                            Divider()
                                .padding(.horizontal, DesignTokens.Spacing.md)
                        }
                        if section.tasks.isEmpty, case .upcoming = state.selection {
                            Label("No tasks due", systemImage: "checkmark.circle")
                                .font(.subheadline)
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                                .padding(.horizontal, DesignTokens.Spacing.md)
                                .padding(.vertical, DesignTokens.Spacing.xs)
                        } else {
                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxs) {
                                ForEach(section.tasks, id: \.id) { task in
                                    let isExpandable = state.selection == .today
                                    TaskRow(
                                        task: task,
                                        dueLabel: TasksUtils.dueLabel(for: task),
                                        repeatLabel: formatRepeatLabel(TasksUtils.recurrenceLabel(for: task)),
                                        selection: state.selection,
                                        isExpanded: isExpandable && expandedTaskIds.contains(task.id),
                                        onComplete: { Task { await viewModel.completeTask(task: task) } },
                                        onOpenNotes: { openNotes(task) },
                                        onSelect: { setActiveTask(task) },
                                        onToggleExpanded: {
                                            guard isExpandable, !task.isPreview else { return }
                                            if expandedTaskIds.contains(task.id) {
                                                expandedTaskIds.remove(task.id)
                                            } else {
                                                expandedTaskIds.insert(task.id)
                                            }
                                        },
                                        menuContent: {
                                        taskMenu(for: task, selection: state.selection)
                                    }
                                    )
                                    .padding(.horizontal, DesignTokens.Spacing.md)
                                }
                            }
                            .padding(.bottom, section.title.isEmpty ? 0 : DesignTokens.Spacing.md)
                        }
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.vertical, DesignTokens.Spacing.lg)
                .frame(maxWidth: DesignTokens.Size.contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                expandedTaskIds.removeAll()
            }
        }
    }

    @ViewBuilder
    private func todaySectionHeader(section: TaskSection, state: TasksViewState) -> some View {
        let iconName = todaySectionIcon(for: section, state: state)
        let targetSelection = todaySectionSelection(for: section, state: state)
        let label = HStack(spacing: 6) {
            if let iconName {
                Image(systemName: iconName)
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            Text(section.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        if let targetSelection {
            Button {
                Task { await viewModel.load(selection: targetSelection) }
            } label: {
                label
            }
            .buttonStyle(.plain)
        } else {
            label
        }
    }

    private func todaySectionIcon(for section: TaskSection, state: TasksViewState) -> String? {
        if section.id.hasPrefix("project:") || state.projectTitleById[section.id] != nil {
            return "list.bullet"
        }
        if state.groupTitleById[section.id] != nil {
            return "square.3.layers.3d"
        }
        return nil
    }

    private func todaySectionSelection(for section: TaskSection, state: TasksViewState) -> TaskSelection? {
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

    private func taskMenu(for task: TaskItem, selection: TaskSelection) -> some View {
        Group {
            Button("Rename") { openRename(task) }
            Button("Edit notes") { openNotes(task) }
            Button("Move to...") { openMove(task) }
            Divider()
            Button(task.repeating == true ? "Edit repeat..." : "Repeat...") { openRepeat(task) }
            Divider()
            if task.repeating != true {
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

    private func tasksCountLabel(for state: TasksViewState) -> String? {
        if state.totalCount == 0 { return nil }
        if state.totalCount == 1 { return "1 task" }
        return "\(state.totalCount) tasks"
    }

    private func openRename(_ task: TaskItem) {
        renameTask = task
        renameValue = task.title
        setActiveTask(task)
    }

}
