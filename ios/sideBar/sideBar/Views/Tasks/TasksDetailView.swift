import SwiftUI

struct TasksDetailView: View {
    @ObservedObject var viewModel: TasksViewModel
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.workspaceColumn) private var workspaceColumn
    @AppStorage(AppStorageKeys.workspaceExpanded) private var isWorkspaceExpanded: Bool = false
    #if os(iOS)
    @AppStorage(AppStorageKeys.workspaceExpandedByRotation) private var isWorkspaceExpandedByRotation: Bool = false
    #endif
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif

    @State var renameTask: TaskItem?
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
            if isCompact {
                compactHeader(state: state)
                Divider()
            } else {
                header(state: state)
                Divider()
            }
            content(state: state)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if shouldShowWorkspaceFloatingActionDock(for: state.selection) {
                HStack {
                    Spacer(minLength: 0)
                    workspaceFloatingActionDock
                        .padding(.trailing, DesignTokens.Spacing.lg)
                        .padding(.bottom, DesignTokens.Spacing.md)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .sheet(item: $renameTask) { task in
            RenameTaskSheet(
                task: task,
                onSave: { title in
                    Task { await viewModel.renameTask(task: task, title: title) }
                },
                onDismiss: { renameTask = nil }
            )
            .phoneSheetGrabBarVisible()
        }
        .deleteConfirmationAlert(
            title: "Delete task",
            isPresented: isDeletePresented,
            message: "This will delete the task and any repeat instances.",
            onConfirm: {
                guard let task = deleteTask else { return }
                Task { await viewModel.deleteTask(task: task) }
                deleteTask = nil
            },
            onCancel: { deleteTask = nil }
        )
        .sheet(item: $notesTask) { task in
            NotesSheet(
                task: task,
                notes: task.notes ?? "",
                onSave: { value in
                    Task { await viewModel.updateNotes(task: task, notes: value) }
                },
                onAutosave: { value in
                    Task { await viewModel.autosaveNotes(task: task, notes: value) }
                },
                onDismiss: { notesTask = nil }
            )
            .phoneSheetGrabBarVisible()
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
            .phoneSheetGrabBarVisible()
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
            .phoneSheetGrabBarVisible()
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
            .phoneSheetGrabBarVisible()
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
                .phoneSheetGrabBarVisible()
            }
        }
        .onReceive(environment.navigation.$shortcutActionEvent) { event in
            guard let event, event.section == .tasks else { return }
            if Self.shortcutActionDoesNotRequireActiveTask(event.action) {
                if event.action == .newItem {
                    viewModel.startNewTask()
                }
                return
            }
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
        .onChange(of: state.selection) { _, _ in
            expandedTaskIds.removeAll()
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
        , trailing: {
            HStack(spacing: DesignTokens.Spacing.sm) {
                if shouldShowExpandButton {
                    expandButton
                }
                if state.totalCount == 0 {
                    Image(systemName: "checkmark")
                        .appFont(.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .accessibilityLabel("No tasks")
                } else if let label = tasksCountLabel(for: state) {
                    Text(label)
                        .appFont(.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }
        })
        .padding(DesignTokens.Spacing.md)
        .frame(height: LayoutMetrics.contentHeaderMinHeight)
    }

    @ViewBuilder
    private func compactHeader(state: TasksViewState) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: state.titleIcon)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Text(state.selectionLabel)
                .appFont(.title3Semibold)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)
            Spacer()
            if shouldShowExpandButton {
                expandButton
            }
            if state.selection != .completed && shouldShowCompactAddButton {
                Button {
                    viewModel.startNewTask()
                } label: {
                    Image(systemName: "plus")
                        .appFont(.subheadline)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New task")
            }
        }
        .padding(DesignTokens.Spacing.md)
        .frame(height: LayoutMetrics.contentHeaderMinHeight)
    }

    private var shouldShowExpandButton: Bool {
        guard workspaceColumn == .primary else { return false }
        #if os(iOS)
        return !isPhone
        #else
        return true
        #endif
    }

    private var shouldShowCompactAddButton: Bool {
        #if os(iOS)
        return !isPhone
        #else
        return true
        #endif
    }

    private var expandButton: some View {
        Button(action: expandTasksView) {
            Image(systemName: expandButtonIconName)
                .appFont(.labelMd)
                .frame(width: 28, height: 20)
                .imageScale(.medium)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(expandButtonLabel)
    }

    private var expandButtonIconName: String {
        isWorkspaceExpanded ? "arrow.up.right.and.arrow.down.left" : "arrow.down.left.and.arrow.up.right"
    }

    private var expandButtonLabel: String {
        isWorkspaceExpanded ? "Exit expanded mode" : "Expand tasks"
    }

    private func expandTasksView() {
        #if os(iOS)
        if !isPhone {
            isWorkspaceExpandedByRotation = false
        }
        #endif
        isWorkspaceExpanded.toggle()
    }

    #if os(iOS)
    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }
    #endif

    @ViewBuilder
    // swiftlint:disable:next function_body_length
    private func content(state: TasksViewState) -> some View {
        if viewModel.isLoading || (isSearchSelection(state.selection) && viewModel.searchPending) {
            LoadingView(
                message: isSearchSelection(state.selection)
                    ? "Loading search results..."
                    : "Loading tasks..."
            )
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
            if state.selection == .none {
                PlaceholderView(
                    title: "Select a list",
                    subtitle: "Pick a task list from the sidebar to get started.",
                    iconName: "checkmark.circle"
                )
            } else {
                PlaceholderView(
                    title: state.selectionLabel == "Today" ? "All done for the day" : "No tasks to show.",
                    subtitle: searchSubtitle(selection: state.selection),
                    iconName: "checkmark.circle"
                )
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    ForEach(state.sections) { section in
                        sectionHeaderView(section: section, state: state)
                        if section.tasks.isEmpty, case .upcoming = state.selection {
                            Label("No tasks due", systemImage: "checkmark.circle")
                                .appFont(.subheadline)
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                                .padding(.leading, DesignTokens.Spacing.md + 14)
                                .padding(.trailing, DesignTokens.Spacing.md)
                                .padding(.vertical, DesignTokens.Spacing.xs)
                                .padding(.bottom, DesignTokens.Spacing.md)
                        } else {
                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxs) {
                                ForEach(section.tasks, id: \.id) { task in
                                    let isExpandable = true
                                    TaskRow(
                                        task: task,
                                        dueLabel: TasksUtils.dueLabel(for: task),
                                        repeatLabel: formatRepeatLabel(TasksUtils.recurrenceLabel(for: task)),
                                        selection: state.selection,
                                        isExpanded: isExpandable && expandedTaskIds.contains(task.id),
                                        onComplete: { Task { await viewModel.completeTask(task: task) } },
                                        onOpenNotes: { openNotes(task) },
                                        onOpenDue: { openDue(task) },
                                        onSelect: { setActiveTask(task) },
                                        onToggleExpanded: {
                                            guard isExpandable, !task.isPreview else { return }
                                            if expandedTaskIds.contains(task.id) {
                                                expandedTaskIds.remove(task.id)
                                            } else {
                                                expandedTaskIds = [task.id]
                                            }
                                        },
                                        onMove: { openMove(task) },
                                        onRepeat: { openRepeat(task) },
                                        onDelete: { deleteTask = task },
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
                .padding(.vertical, DesignTokens.Spacing.lg)
                .frame(maxWidth: SideBarMarkdownLayout.maxContentWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .contentShape(Rectangle())
            .gesture(
                TapGesture().onEnded {
                    expandedTaskIds.removeAll()
                },
                including: .gesture
            )
        }
    }

    @ViewBuilder
    private func sectionHeaderView(section: TaskSection, state: TasksViewState) -> some View {
        if section.title.isEmpty {
            EmptyView()
        } else {
            switch state.selection {
            case .today:
                todaySectionHeader(section: section, state: state)
                    .padding(.horizontal, DesignTokens.Spacing.md)
            case .upcoming, .completed:
                sectionHeaderLabel(
                    title: section.title,
                    iconName: "calendar"
                )
                .padding(.horizontal, DesignTokens.Spacing.md)
            case .group:
                groupSectionHeader(section: section, state: state)
                    .padding(.horizontal, DesignTokens.Spacing.md)
            default:
                Text(section.title)
                    .appFont(.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .padding(.horizontal, DesignTokens.Spacing.md)
            }
            Divider()
                .padding(.horizontal, DesignTokens.Spacing.md)
        }
    }

    @ViewBuilder
    private func todaySectionHeader(section: TaskSection, state: TasksViewState) -> some View {
        let iconName = todaySectionIcon(for: section, state: state)
        let targetSelection = todaySectionSelection(for: section, state: state)
        let label = sectionHeaderLabel(title: section.title, iconName: iconName)
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

    private func groupSectionHeader(section: TaskSection, state: TasksViewState) -> some View {
        let iconName: String?
        if section.id != "group" {
            iconName = "list.bullet"
        } else {
            iconName = nil
        }
        return sectionHeaderLabel(title: section.title, iconName: iconName)
    }

    private func sectionHeaderLabel(title: String, iconName: String?) -> some View {
        HStack(spacing: 6) {
            if let iconName {
                Image(systemName: iconName)
                    .appFont(.subheadline)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            Text(title)
                .appFont(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
    }

}
