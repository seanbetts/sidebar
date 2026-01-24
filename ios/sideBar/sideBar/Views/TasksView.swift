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

private struct TasksDetailView: View {
    @ObservedObject var viewModel: TasksViewModel
    @EnvironmentObject private var environment: AppEnvironment
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @State private var renameTask: TaskItem? = nil
    @State private var renameValue: String = ""
    @State private var notesTask: TaskItem? = nil
    @State private var dueTask: TaskItem? = nil
    @State private var dueDate: Date = Date()
    @State private var moveTask: TaskItem? = nil
    @State private var selectedListId: String = ""
    @State private var repeatTask: TaskItem? = nil
    @State private var repeatType: RepeatType = .daily
    @State private var repeatInterval: Int = 1
    @State private var repeatStartDate: Date = Date()
    @State private var deleteTask: TaskItem? = nil
    @State private var activeTaskId: String? = nil

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
                LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    ForEach(state.sections) { section in
                        if !section.title.isEmpty {
                            Text(section.title)
                                .font(.caption)
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                                .padding(.horizontal, DesignTokens.Spacing.md)
                        }
                        ForEach(section.tasks, id: \.id) { task in
                            TaskRow(
                                task: task,
                                subtitle: TasksUtils.taskSubtitle(
                                    task: task,
                                    selection: state.selection,
                                    selectionLabel: state.selectionLabel,
                                    projectTitleById: state.projectTitleById,
                                    groupTitleById: state.groupTitleById
                                ),
                                dueLabel: TasksUtils.dueLabel(for: task),
                                repeatLabel: formatRepeatLabel(TasksUtils.recurrenceLabel(for: task)),
                                selection: state.selection,
                                onComplete: { Task { await viewModel.completeTask(task: task) } },
                                onOpenNotes: { openNotes(task) },
                                onSelect: { setActiveTask(task) }
                            ) {
                                taskMenu(for: task, selection: state.selection)
                            }
                        }
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.vertical, DesignTokens.Spacing.lg)
                .frame(maxWidth: DesignTokens.Size.contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
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

    private func commitRename() {
        guard let task = renameTask else { return }
        let newTitle = renameValue.trimmingCharacters(in: .whitespacesAndNewlines)
        renameTask = nil
        if newTitle.isEmpty || newTitle == task.title { return }
        Task { await viewModel.renameTask(task: task, title: newTitle) }
    }

    private func openNotes(_ task: TaskItem) {
        notesTask = task
        setActiveTask(task)
    }

    private func openDue(_ task: TaskItem) {
        dueTask = task
        dueDate = TasksUtils.parseTaskDate(task) ?? Date()
        setActiveTask(task)
    }

    private func openMove(_ task: TaskItem) {
        moveTask = task
        selectedListId = task.projectId ?? task.groupId ?? ""
        setActiveTask(task)
    }

    private func openRepeat(_ task: TaskItem) {
        repeatTask = task
        if let rule = task.recurrenceRule {
            repeatType = RepeatType(rawValue: rule.type) ?? .daily
            repeatInterval = max(1, rule.interval ?? 1)
        } else {
            repeatType = .daily
            repeatInterval = 1
        }
        repeatStartDate = TasksUtils.parseTaskDate(task) ?? Date()
        setActiveTask(task)
    }

    private func formatRepeatLabel(_ label: String?) -> String? {
        guard let label else { return nil }
        return label
            .split(separator: " ")
            .map { $0.isEmpty ? "" : $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private func setActiveTask(_ task: TaskItem) {
        guard !task.isPreview else { return }
        activeTaskId = task.id
    }

    private func activeTask(in state: TasksViewState) -> TaskItem? {
        guard let activeTaskId else { return nil }
        for section in state.sections {
            if let task = section.tasks.first(where: { $0.id == activeTaskId && !$0.isPreview }) {
                return task
            }
        }
        return nil
    }

    private func buildRecurrenceRule(type: RepeatType, interval: Int, startDate: Date) -> RecurrenceRule? {
        switch type {
        case .none:
            return nil
        case .daily:
            return RecurrenceRule(type: "daily", interval: interval, weekday: nil, dayOfMonth: nil)
        case .weekly:
            let weekday = Calendar.current.component(.weekday, from: startDate) - 1
            return RecurrenceRule(type: "weekly", interval: interval, weekday: weekday, dayOfMonth: nil)
        case .monthly:
            let day = Calendar.current.component(.day, from: startDate)
            return RecurrenceRule(type: "monthly", interval: interval, weekday: nil, dayOfMonth: day)
        }
    }

    private func nextWeekdayOffset(targetWeekday: Int) -> Int {
        let current = Calendar.current.component(.weekday, from: Date()) - 1
        let delta = (targetWeekday - current + 7) % 7
        return delta == 0 ? 7 : delta
    }

    private func isSearchSelection(_ selection: TaskSelection) -> Bool {
        if case .search = selection {
            return true
        }
        return false
    }

    private func searchSubtitle(selection: TaskSelection) -> String? {
        guard case .search(let query) = selection else { return nil }
        return query.isEmpty ? "No results for your search." : "No results for \"\(query)\""
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    private var isRenamePresented: Binding<Bool> {
        Binding(
            get: { renameTask != nil },
            set: { newValue in
                if !newValue { renameTask = nil }
            }
        )
    }

    private var isDeletePresented: Binding<Bool> {
        Binding(
            get: { deleteTask != nil },
            set: { newValue in
                if !newValue { deleteTask = nil }
            }
        )
    }

    private var isNewTaskPresented: Binding<Bool> {
        Binding(
            get: { viewModel.newTaskDraft != nil },
            set: { newValue in
                if !newValue { viewModel.cancelNewTask() }
            }
        )
    }
}
