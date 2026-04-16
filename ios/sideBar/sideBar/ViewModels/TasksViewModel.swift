import Foundation
import Combine
import sideBarShared

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
    let widgetDataManager: WidgetDataManager
    let toastCenter: ToastCenter
    let networkStatus: any NetworkStatusProviding
    let searchDebounceNanoseconds: UInt64
    let realtimeRefreshDelayNanoseconds: UInt64
    var cancellables = Set<AnyCancellable>()
    var searchDebounce: Task<Void, Never>?
    var realtimeRefreshTask: Task<Void, Never>?
    var lastNonSearchSelection: TaskSelection = .today

    public init(
        api: any TasksProviding,
        store: TasksStore,
        widgetDataManager: WidgetDataManager? = nil,
        toastCenter: ToastCenter,
        networkStatus: any NetworkStatusProviding,
        searchDebounceNanoseconds: UInt64 = 350_000_000,
        realtimeRefreshDelayNanoseconds: UInt64 = 200_000_000
    ) {
        self.api = api
        self.store = store
        self.widgetDataManager = widgetDataManager ?? .shared
        self.toastCenter = toastCenter
        self.networkStatus = networkStatus
        self.searchDebounceNanoseconds = searchDebounceNanoseconds
        self.realtimeRefreshDelayNanoseconds = realtimeRefreshDelayNanoseconds

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
        widgetDataManager.store(data, for: .tasks)
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
            widgetDataManager.store(data, for: .tasks)
        } catch {
            // Silently fail - widget will use cached data
        }
    }

    private func buildWidgetTaskData(tasks: [WidgetTask], remainingCount: Int) -> WidgetTaskData {
        let now = Date()
        let previous: WidgetTaskData = widgetDataManager.load(for: .tasks)
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
}
