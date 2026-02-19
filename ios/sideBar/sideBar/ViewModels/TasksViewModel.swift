import Foundation
import Combine

@MainActor
/// Manages tasks state, networking, and user actions for the tasks UI.
public final class TasksViewModel: ObservableObject {
    @Published var localErrorMessage: String?
    @Published public var searchQuery: String = ""
    @Published public var newTaskDraft: TaskDraft?
    @Published public internal(set) var newTaskSaving: Bool = false
    @Published public internal(set) var newTaskError: String = ""
    @Published public internal(set) var filteredUpcomingCount: Int?
    @Published public internal(set) var panelGroupsSorted: [TaskGroup] = []
    @Published public internal(set) var panelProjectsByGroup: [String: [TaskProject]] = [:]
    @Published public internal(set) var panelOrphanProjects: [TaskProject] = []
    @Published public internal(set) var panelGroupCounts: [String: Int] = [:]
    @Published public internal(set) var panelProjectCounts: [String: Int] = [:]

    let api: any TasksProviding
    let store: TasksStore
    let toastCenter: ToastCenter
    let networkStatus: any NetworkStatusProviding
    var cancellables = Set<AnyCancellable>()
    var searchDebounce: Task<Void, Never>?
    var realtimeRefreshTask: Task<Void, Never>?
    var lastNonSearchSelection: TaskSelection = .today

    public init(
        api: any TasksProviding,
        store: TasksStore,
        toastCenter: ToastCenter,
        networkStatus: any NetworkStatusProviding
    ) {
        self.api = api
        self.store = store
        self.toastCenter = toastCenter
        self.networkStatus = networkStatus

        store.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(store.$groups, store.$projects, store.$counts)
            .sink { [weak self] groups, projects, counts in
                self?.rebuildPanelDerivedState(groups: groups, projects: projects, counts: counts)
            }
            .store(in: &cancellables)
    }

    public var tasks: [TaskItem] { store.tasks }
    public var groups: [TaskGroup] { store.groups }
    public var projects: [TaskProject] { store.projects }
    public var counts: TaskCountsResponse? { store.counts }
    public var isLoading: Bool { store.isLoading }
    public var searchPending: Bool { store.searchPending }
    public var selection: TaskSelection { store.selection }
    public var errorMessage: String? { localErrorMessage ?? store.errorMessage }

    public func load(selection: TaskSelection, force: Bool = false) async {
        localErrorMessage = nil
        if selection == .none {
            await store.load(selection: selection, force: force)
            return
        }
        if !selection.isSearch {
            lastNonSearchSelection = selection
        }
        await store.load(selection: selection, force: force)

        // Update the cached filtered upcoming count when loading Upcoming
        if case .upcoming = selection {
            filteredUpcomingCount = viewState.totalCount
        }

        // Update widget data when loading Today's tasks
        if case .today = selection {
            updateWidgetData()
        }
    }

    /// Updates widget data with current today tasks (when already on Today view)
    func updateWidgetData() {
        let projectTitleById = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.title) })
        let groupTitleById = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0.title) })
        let todayTasks = TasksUtils.sortByDueDate(
            tasks.filter { $0.status != "completed" && $0.status != "project" }
        )
        let widgetTasks = todayTasks.prefix(10).map { task in
            WidgetTask(
                from: task,
                projectName: task.projectId.flatMap { projectTitleById[$0] },
                groupName: task.groupId.flatMap { groupTitleById[$0] }
            )
        }
        let data = buildWidgetTaskData(
            tasks: Array(widgetTasks),
            remainingCount: todayTasks.count
        )
        WidgetDataManager.shared.store(data, for: .tasks)
    }

    /// Fetches today's tasks and updates widget data (works from any view)
    func refreshWidgetData() async {
        do {
            let response = try await api.list(scope: "today")
            let projectTitleById = Dictionary(uniqueKeysWithValues: response.projects?.map { ($0.id, $0.title) } ?? [])
            let groupTitleById = Dictionary(uniqueKeysWithValues: response.groups?.map { ($0.id, $0.title) } ?? [])
            let todayTasks = TasksUtils.sortByDueDate(
                response.tasks.filter { $0.status != "completed" && $0.status != "project" }
            )
            let widgetTasks = todayTasks.prefix(10).map { task in
                WidgetTask(
                    from: task,
                    projectName: task.projectId.flatMap { projectTitleById[$0] },
                    groupName: task.groupId.flatMap { groupTitleById[$0] }
                )
            }
            let data = buildWidgetTaskData(
                tasks: Array(widgetTasks),
                remainingCount: todayTasks.count
            )
            WidgetDataManager.shared.store(data, for: .tasks)
        } catch {
            // Silently fail - widget will use cached data
        }
    }

    private func buildWidgetTaskData(tasks: [WidgetTask], remainingCount: Int) -> WidgetTaskData {
        let now = Date()
        let previous: WidgetTaskData = WidgetDataManager.shared.load(for: .tasks)
        let calendar = Calendar.current

        let progressCompletedCount: Int
        let progressTotalCount: Int

        if calendar.isDate(previous.lastUpdated, inSameDayAs: now) {
            let persistedCompleted = max(0, previous.progressCompletedCount)
            let persistedTotal = max(0, previous.progressTotalCount)
            let nextTotal = max(persistedTotal, remainingCount + persistedCompleted)
            let inferredCompleted = max(persistedCompleted, nextTotal - remainingCount)
            progressTotalCount = nextTotal
            progressCompletedCount = min(inferredCompleted, nextTotal)
        } else {
            progressTotalCount = max(0, remainingCount)
            progressCompletedCount = 0
        }

        return WidgetTaskData(
            tasks: tasks,
            totalCount: remainingCount,
            progressCompletedCount: progressCompletedCount,
            progressTotalCount: progressTotalCount,
            lastUpdated: now
        )
    }

    public func loadCounts(force: Bool = false) async {
        localErrorMessage = nil
        await store.loadCounts(force: force)
    }

    public func reset() {
        searchDebounce?.cancel()
        searchDebounce = nil
        realtimeRefreshTask?.cancel()
        localErrorMessage = nil
        searchQuery = ""
        newTaskDraft = nil
        newTaskSaving = false
        newTaskError = ""
        filteredUpcomingCount = nil
        lastNonSearchSelection = .today
        panelGroupsSorted = []
        panelProjectsByGroup = [:]
        panelOrphanProjects = []
        panelGroupCounts = [:]
        panelProjectCounts = [:]
    }

    private func rebuildPanelDerivedState(
        groups: [TaskGroup],
        projects: [TaskProject],
        counts: TaskCountsResponse?
    ) {
        panelGroupsSorted = groups.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }

        let sortedProjects = projects.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        var projectsByGroup: [String: [TaskProject]] = [:]
        var orphanProjects: [TaskProject] = []
        for project in sortedProjects {
            if let groupId = project.groupId {
                projectsByGroup[groupId, default: []].append(project)
            } else {
                orphanProjects.append(project)
            }
        }
        panelProjectsByGroup = projectsByGroup
        panelOrphanProjects = orphanProjects

        var groupCounts = Dictionary(
            uniqueKeysWithValues: (counts?.groups ?? []).map { ($0.id, $0.count) }
        )
        for group in groups where groupCounts[group.id] == nil {
            groupCounts[group.id] = 0
        }
        panelGroupCounts = groupCounts

        var projectCounts = Dictionary(
            uniqueKeysWithValues: (counts?.projects ?? []).map { ($0.id, $0.count) }
        )
        for project in projects where projectCounts[project.id] == nil {
            projectCounts[project.id] = 0
        }
        panelProjectCounts = projectCounts
    }
}

extension TasksViewModel {
    public var viewState: TasksViewState {
        let filteredTasks = tasks.filter { $0.status != "project" }
        let expanded = selection == .today || selection == .completed
            ? filteredTasks
            : TasksUtils.expandRepeatingTasks(filteredTasks)

        let sortedTasks: [TaskItem]
        switch selection {
        case .none:
            sortedTasks = []
        case .group(let groupId):
            let projectIds = Set(projects.filter { $0.groupId == groupId }.map { $0.id })
            let scoped = expanded.filter { task in
                if let projectId = task.projectId {
                    return projectIds.isEmpty || projectIds.contains(projectId)
                }
                return task.groupId == groupId || projectIds.isEmpty
            }
            sortedTasks = TasksUtils.sortByDueDate(scoped)
        case .project(let projectId):
            let scoped = expanded.filter { $0.projectId == projectId }
            sortedTasks = TasksUtils.sortByDueDate(scoped)
        case .search:
            sortedTasks = TasksUtils.sortByDueDate(expanded)
        default:
            sortedTasks = expanded
        }

        let projectTitleById = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.title) })
        let groupTitleById = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0.title) })

        let selectionLabel: String
        let titleIcon: String
        let sections: [TaskSection]

        switch selection {
        case .none:
            selectionLabel = "Tasks"
            titleIcon = "checkmark.square"
            sections = []
        case .today:
            selectionLabel = "Today"
            titleIcon = "calendar"
            sections = TasksUtils.buildTodaySections(
                tasks: sortedTasks,
                groups: groups,
                projects: projects,
                groupTitleById: groupTitleById,
                projectTitleById: projectTitleById
            )
        case .upcoming:
            selectionLabel = "Upcoming"
            titleIcon = "calendar.badge.clock"
            sections = TasksUtils.buildUpcomingSections(tasks: sortedTasks)
        case .completed:
            selectionLabel = "Completed"
            titleIcon = "calendar.badge.checkmark"
            sections = TasksUtils.buildCompletedSections(tasks: sortedTasks)
        case .inbox:
            selectionLabel = "Inbox"
            titleIcon = "tray"
            sections = sortedTasks.isEmpty ? [] : [TaskSection(id: "all", title: "", tasks: sortedTasks)]
        case .group(let id):
            let title = groups.first(where: { $0.id == id })?.title ?? "Group"
            selectionLabel = title
            titleIcon = "square.3.layers.3d"
            sections = TasksUtils.buildGroupSections(
                tasks: sortedTasks,
                groupId: id,
                groupTitle: title,
                projects: projects
            )
        case .project(let id):
            selectionLabel = projects.first(where: { $0.id == id })?.title ?? "Project"
            titleIcon = "list.bullet"
            sections = sortedTasks.isEmpty ? [] : [TaskSection(id: "all", title: "", tasks: sortedTasks)]
        case .search(let query):
            selectionLabel = query.isEmpty ? "Search" : "Search: \(query)"
            titleIcon = "magnifyingglass"
            sections = TasksUtils.buildSearchSections(tasks: sortedTasks, groups: groups)
        }

        let totalCount = sections.reduce(0) { result, section in
            result + section.tasks.filter { !$0.isPreview }.count
        }

        return TasksViewState(
            selectionLabel: selectionLabel,
            titleIcon: titleIcon,
            sections: sections,
            totalCount: totalCount,
            selection: selection,
            projectTitleById: projectTitleById,
            groupTitleById: groupTitleById
        )
    }

    public func startNewTask() {
        let baseSelection = selection.isSearch ? lastNonSearchSelection : selection
        let dueDate: Date
        if case .upcoming = baseSelection {
            dueDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        } else {
            dueDate = Date()
        }
        var listId: String?
        var listName: String?

        switch baseSelection {
        case .none:
            break
        case .group(let id):
            listId = id
            listName = groups.first(where: { $0.id == id })?.title
        case .project(let id):
            listId = id
            listName = projects.first(where: { $0.id == id })?.title
        case .today, .upcoming, .inbox, .search, .completed:
            if let home = groups.first(where: { $0.title.lowercased() == "home" }) {
                listId = home.id
                listName = home.title
            } else if let first = groups.first {
                listId = first.id
                listName = first.title
            }
        }

        newTaskDraft = TaskDraft(
            title: "",
            notes: "",
            dueDate: dueDate,
            listId: listId,
            listName: listName,
            selection: baseSelection
        )
        newTaskError = ""
    }

    public func cancelNewTask() {
        newTaskDraft = nil
        newTaskError = ""
    }

    public func createTask(title: String, notes: String, dueDate: Date?, listId: String?) async {
        guard !newTaskSaving else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let draft = newTaskDraft else { return }
        guard !trimmed.isEmpty else {
            newTaskError = "Title is required."
            return
        }
        let listId = listId ?? draft.listId

        newTaskSaving = true
        newTaskError = ""
        defer { newTaskSaving = false }

        let dueDateKey = dueDate.map { TasksUtils.formatDateKey($0) }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesPayload = trimmedNotes.isEmpty ? nil : trimmedNotes
        let operation = TaskOperationPayload(
            operationId: TaskOperationId.make(),
            op: "add",
            id: nil,
            title: trimmed,
            notes: notesPayload,
            listId: listId,
            dueDate: dueDateKey,
            startDate: nil,
            recurrenceRule: nil,
            clientUpdatedAt: nil
        )

        if shouldQueueTaskWrites {
            do {
                try await store.enqueueOperation(operation)
                store.applyLocalOperation(operation)
                newTaskDraft = nil
                toastCenter.show(message: "Task queued for sync.")
            } catch WriteQueueError.queueFull {
                newTaskError = "Sync queue full. Review pending changes."
            } catch {
                newTaskError = "Failed to queue task"
            }
            return
        }

        do {
            _ = try await api.apply(TaskOperationBatch(operations: [operation]))
            newTaskDraft = nil
            await load(selection: selection, force: true)
            await loadCounts(force: true)
            await refreshWidgetData()
        } catch {
            newTaskError = ErrorMapping.message(for: error)
        }
    }

    public func createGroup(title: String) async throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = try await api.createGroup(title: trimmed)
        await load(selection: selection, force: true)
        await loadCounts(force: true)
    }

    public func renameGroup(groupId: String, title: String) async throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = try await api.renameGroup(groupId: groupId, title: trimmed)
        await load(selection: selection, force: true)
        await loadCounts(force: true)
    }

    public func deleteGroup(groupId: String) async throws {
        let projectIds = projects.filter { $0.groupId == groupId }.map { $0.id }
        let nextSelection: TaskSelection
        switch selection {
        case .group(let id) where id == groupId:
            nextSelection = .none
        case .project(let id) where projectIds.contains(id):
            nextSelection = .none
        default:
            nextSelection = selection
        }
        try await api.deleteGroup(groupId: groupId)
        await load(selection: nextSelection, force: true)
        await loadCounts(force: true)
    }

    public func createProject(title: String, groupId: String?) async throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = try await api.createProject(title: trimmed, groupId: groupId)
        await load(selection: selection, force: true)
        await loadCounts(force: true)
    }

    public func renameProject(projectId: String, title: String) async throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = try await api.renameProject(projectId: projectId, title: trimmed)
        await load(selection: selection, force: true)
        await loadCounts(force: true)
    }

    public func deleteProject(projectId: String) async throws {
        let nextSelection: TaskSelection
        switch selection {
        case .project(let id) where id == projectId:
            nextSelection = .none
        default:
            nextSelection = selection
        }
        try await api.deleteProject(projectId: projectId)
        await load(selection: nextSelection, force: true)
        await loadCounts(force: true)
    }
}
