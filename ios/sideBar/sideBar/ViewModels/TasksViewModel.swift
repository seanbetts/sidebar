import Foundation
import Combine

@MainActor
public final class TasksViewModel: ObservableObject {
    @Published public private(set) var tasks: [TaskItem] = []
    @Published public private(set) var areas: [TaskArea] = []
    @Published public private(set) var projects: [TaskProject] = []
    @Published public private(set) var counts: TaskCountsResponse? = nil
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var searchPending: Bool = false
    @Published public private(set) var errorMessage: String? = nil
    @Published public private(set) var selection: TaskSelection = .today
    @Published public var searchQuery: String = ""
    @Published public var newTaskDraft: TaskDraft? = nil
    @Published public private(set) var newTaskSaving: Bool = false
    @Published public private(set) var newTaskError: String = ""

    private let api: any TasksProviding
    private let store: TasksStore
    private let toastCenter: ToastCenter
    private var cancellables = Set<AnyCancellable>()
    private var searchDebounce: Task<Void, Never>? = nil
    private var lastNonSearchSelection: TaskSelection = .today

    public var viewState: TasksViewState {
        let filteredTasks = tasks.filter { $0.status != "project" }
        let expanded = TasksUtils.expandRepeatingTasks(filteredTasks)

        let sortedTasks: [TaskItem]
        switch selection {
        case .area(let areaId):
            let projectIds = Set(projects.filter { $0.areaId == areaId }.map { $0.id })
            let scoped = expanded.filter { task in
                if let projectId = task.projectId {
                    return projectIds.isEmpty || projectIds.contains(projectId)
                }
                return task.areaId == areaId || projectIds.isEmpty
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
        let areaTitleById = Dictionary(uniqueKeysWithValues: areas.map { ($0.id, $0.title) })

        let selectionLabel: String
        let titleIcon: String
        let sections: [TaskSection]

        switch selection {
        case .today:
            selectionLabel = "Today"
            titleIcon = "calendar"
            sections = TasksUtils.buildTodaySections(
                tasks: sortedTasks,
                areas: areas,
                projects: projects,
                areaTitleById: areaTitleById,
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
        case .area(let id):
            let title = areas.first(where: { $0.id == id })?.title ?? "Group"
            selectionLabel = title
            titleIcon = "square.3.layers.3d"
            sections = TasksUtils.buildAreaSections(
                tasks: sortedTasks,
                areaId: id,
                areaTitle: title,
                projects: projects
            )
        case .project(let id):
            selectionLabel = projects.first(where: { $0.id == id })?.title ?? "Project"
            titleIcon = "list.bullet"
            sections = sortedTasks.isEmpty ? [] : [TaskSection(id: "all", title: "", tasks: sortedTasks)]
        case .search(let query):
            selectionLabel = query.isEmpty ? "Search" : "Search: \(query)"
            titleIcon = "magnifyingglass"
            sections = TasksUtils.buildSearchSections(tasks: sortedTasks, areas: areas)
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
            areaTitleById: areaTitleById
        )
    }

    public init(api: any TasksProviding, store: TasksStore, toastCenter: ToastCenter) {
        self.api = api
        self.store = store
        self.toastCenter = toastCenter

        store.$tasks
            .sink { [weak self] tasks in
                self?.tasks = tasks
            }
            .store(in: &cancellables)

        store.$areas
            .sink { [weak self] areas in
                self?.areas = areas
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
        var listId: String? = nil
        var listName: String? = nil

        switch baseSelection {
        case .area(let id):
            listId = id
            listName = areas.first(where: { $0.id == id })?.title
        case .project(let id):
            listId = id
            listName = projects.first(where: { $0.id == id })?.title
        case .today, .upcoming, .inbox, .search:
            if let home = areas.first(where: { $0.title.lowercased() == "home" }) {
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

    public func setErrorMessage(_ message: String) {
        errorMessage = message
    }

    public func completeTask(task: TaskItem) async {
        await applyTaskOperation(
            TaskOperationPayload(
                operationId: TaskOperationId.make(),
                op: "complete",
                id: task.id,
                clientUpdatedAt: task.updatedAt
            )
        )
    }

    public func renameTask(task: TaskItem, title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await applyTaskOperation(
            TaskOperationPayload(
                operationId: TaskOperationId.make(),
                op: "rename",
                id: task.id,
                title: trimmed,
                clientUpdatedAt: task.updatedAt
            )
        )
    }

    public func updateNotes(task: TaskItem, notes: String) async {
        await applyTaskOperation(
            TaskOperationPayload(
                operationId: TaskOperationId.make(),
                op: "notes",
                id: task.id,
                notes: notes,
                clientUpdatedAt: task.updatedAt
            )
        )
    }

    public func moveTask(task: TaskItem, listId: String?) async {
        await applyTaskOperation(
            TaskOperationPayload(
                operationId: TaskOperationId.make(),
                op: "move",
                id: task.id,
                listId: listId,
                clientUpdatedAt: task.updatedAt
            )
        )
    }

    public func setDueDate(task: TaskItem, date: Date?) async {
        await applyTaskOperation(
            TaskOperationPayload(
                operationId: TaskOperationId.make(),
                op: "set_due",
                id: task.id,
                dueDate: date.map { TasksUtils.formatDateKey($0) },
                clientUpdatedAt: task.updatedAt
            )
        )
    }

    public func deferTask(task: TaskItem, days: Int) async {
        let baseDate = TasksUtils.parseTaskDate(task) ?? Date()
        let nextDate = Calendar.current.date(byAdding: .day, value: days, to: baseDate)
        await applyTaskOperation(
            TaskOperationPayload(
                operationId: TaskOperationId.make(),
                op: "defer",
                id: task.id,
                dueDate: nextDate.map { TasksUtils.formatDateKey($0) },
                clientUpdatedAt: task.updatedAt
            )
        )
    }

    public func clearDueDate(task: TaskItem) async {
        await applyTaskOperation(
            TaskOperationPayload(
                operationId: TaskOperationId.make(),
                op: "clear_due",
                id: task.id,
                clientUpdatedAt: task.updatedAt
            )
        )
    }

    public func setRepeat(task: TaskItem, rule: RecurrenceRule?, startDate: Date?) async {
        await applyTaskOperation(
            TaskOperationPayload(
                operationId: TaskOperationId.make(),
                op: "set_repeat",
                id: task.id,
                startDate: startDate.map { TasksUtils.formatDateKey($0) },
                recurrenceRule: rule,
                clientUpdatedAt: task.updatedAt
            )
        )
    }

    public func deleteTask(task: TaskItem) async {
        await applyTaskOperation(
            TaskOperationPayload(
                operationId: TaskOperationId.make(),
                op: "trash",
                id: task.id,
                clientUpdatedAt: task.updatedAt
            )
        )
    }

    private func applyTaskOperation(_ operation: TaskOperationPayload) async {
        errorMessage = nil
        do {
            let response = try await api.apply(TaskOperationBatch(operations: [operation]))
            if !response.nextTasks.isEmpty {
                let message = response.nextTasks.count == 1
                    ? "Next instance scheduled: \"\(response.nextTasks[0].title)\""
                    : "Next instances scheduled: \(response.nextTasks.count)"
                toastCenter.show(message: message)
            }
            await load(selection: selection, force: true)
            await loadCounts(force: true)
        } catch {
            errorMessage = ErrorMapping.message(for: error)
        }
    }
}

private extension TaskSelection {
    var isSearch: Bool {
        if case .search = self {
            return true
        }
        return false
    }
}

public struct TasksViewState: Equatable {
    public let selectionLabel: String
    public let titleIcon: String
    public let sections: [TaskSection]
    public let totalCount: Int
    public let selection: TaskSelection
    public let projectTitleById: [String: String]
    public let areaTitleById: [String: String]
}
