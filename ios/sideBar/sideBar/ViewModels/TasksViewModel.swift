import Foundation
import Combine

@MainActor
/// Manages tasks state, networking, and user actions for the tasks UI.
public final class TasksViewModel: ObservableObject {
    @Published public private(set) var tasks: [TaskItem] = []
    @Published public private(set) var groups: [TaskGroup] = []
    @Published public private(set) var projects: [TaskProject] = []
    @Published public private(set) var counts: TaskCountsResponse?
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var searchPending: Bool = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var selection: TaskSelection = .today
    @Published public var searchQuery: String = ""
    @Published public var newTaskDraft: TaskDraft?
    @Published public private(set) var newTaskSaving: Bool = false
    @Published public private(set) var newTaskError: String = ""

    private let api: any TasksProviding
    private let store: TasksStore
    private let toastCenter: ToastCenter
    private var cancellables = Set<AnyCancellable>()
    private var searchDebounce: Task<Void, Never>?
    private var lastNonSearchSelection: TaskSelection = .today

    public init(api: any TasksProviding, store: TasksStore, toastCenter: ToastCenter) {
        self.api = api
        self.store = store
        self.toastCenter = toastCenter

        store.$tasks
            .sink { [weak self] tasks in
                self?.tasks = tasks
            }
            .store(in: &cancellables)

        store.$groups
            .sink { [weak self] groups in
                self?.groups = groups
            }
            .store(in: &cancellables)

        store.$projects
            .sink { [weak self] projects in
                self?.projects = projects
            }
            .store(in: &cancellables)

        store.$counts
            .sink { [weak self] counts in
                self?.counts = counts
            }
            .store(in: &cancellables)

        store.$isLoading
            .sink { [weak self] isLoading in
                self?.isLoading = isLoading
            }
            .store(in: &cancellables)

        store.$searchPending
            .sink { [weak self] searchPending in
                self?.searchPending = searchPending
            }
            .store(in: &cancellables)

        store.$errorMessage
            .sink { [weak self] error in
                self?.errorMessage = error
            }
            .store(in: &cancellables)

        store.$selection
            .sink { [weak self] selection in
                self?.selection = selection
            }
            .store(in: &cancellables)
    }

    public func load(selection: TaskSelection, force: Bool = false) async {
        if !selection.isSearch {
            lastNonSearchSelection = selection
        }
        await store.load(selection: selection, force: force)
    }

    public func loadCounts(force: Bool = false) async {
        await store.loadCounts(force: force)
    }
}

extension TasksViewModel {
    public var viewState: TasksViewState {
        let filteredTasks = tasks.filter { $0.status != "project" }
        let expanded = selection == .today
            ? filteredTasks
            : TasksUtils.expandRepeatingTasks(filteredTasks)

        let sortedTasks: [TaskItem]
        switch selection {
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

    public func updateSearch(query: String) {
        searchQuery = query
        searchDebounce?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchDebounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self else { return }
            if trimmed.isEmpty {
                await self.load(selection: self.lastNonSearchSelection)
            } else {
                await self.load(selection: .search(query: trimmed))
            }
        }
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
        case .group(let id):
            listId = id
            listName = groups.first(where: { $0.id == id })?.title
        case .project(let id):
            listId = id
            listName = projects.first(where: { $0.id == id })?.title
        case .today, .upcoming, .inbox, .search:
            if let home = groups.first(where: { $0.title.lowercased() == "home" }) {
                listId = home.id
                listName = home.title
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

        do {
            _ = try await api.apply(TaskOperationBatch(operations: [operation]))
            newTaskDraft = nil
            await load(selection: selection, force: true)
            await loadCounts(force: true)
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

    public func createProject(title: String, groupId: String?) async throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = try await api.createProject(title: trimmed, groupId: groupId)
        await load(selection: selection, force: true)
        await loadCounts(force: true)
    }
}
