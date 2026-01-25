import SwiftUI

extension TasksDetailView {
    func commitRename() {
        guard let task = renameTask else { return }
        let newTitle = renameValue.trimmingCharacters(in: .whitespacesAndNewlines)
        renameTask = nil
        if newTitle.isEmpty || newTitle == task.title { return }
        Task { await viewModel.renameTask(task: task, title: newTitle) }
    }

    func openNotes(_ task: TaskItem) {
        notesTask = task
        setActiveTask(task)
    }

    func openDue(_ task: TaskItem) {
        dueTask = task
        dueDate = TasksUtils.parseTaskDate(task) ?? Date()
        setActiveTask(task)
    }

    func openMove(_ task: TaskItem) {
        moveTask = task
        selectedListId = task.projectId ?? task.groupId ?? ""
        setActiveTask(task)
    }

    func openRepeat(_ task: TaskItem) {
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

    func formatRepeatLabel(_ label: String?) -> String? {
        guard let label else { return nil }
        return label
            .split(separator: " ")
            .map { $0.isEmpty ? "" : $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    func setActiveTask(_ task: TaskItem) {
        guard !task.isPreview else { return }
        activeTaskId = task.id
    }

    func activeTask(in state: TasksViewState) -> TaskItem? {
        guard let activeTaskId else { return nil }
        for section in state.sections {
            if let task = section.tasks.first(where: { $0.id == activeTaskId && !$0.isPreview }) {
                return task
            }
        }
        return nil
    }

    /// Builds a recurrence rule from the repeat sheet inputs.
    /// Note: weekday uses 0-indexed format (0=Sun, 1=Mon, ..., 6=Sat) to match server API.
    func buildRecurrenceRule(type: RepeatType, interval: Int, startDate: Date) -> RecurrenceRule? {
        switch type {
        case .none:
            return nil
        case .daily:
            return RecurrenceRule(type: "daily", interval: interval, weekday: nil, dayOfMonth: nil)
        case .weekly:
            // Calendar.component(.weekday) returns 1-7 (Sun=1), convert to 0-6 for API
            let weekday = Calendar.current.component(.weekday, from: startDate) - 1
            return RecurrenceRule(type: "weekly", interval: interval, weekday: weekday, dayOfMonth: nil)
        case .monthly:
            let day = Calendar.current.component(.day, from: startDate)
            return RecurrenceRule(type: "monthly", interval: interval, weekday: nil, dayOfMonth: day)
        }
    }

    func nextWeekdayOffset(targetWeekday: Int) -> Int {
        let current = Calendar.current.component(.weekday, from: Date()) - 1
        let delta = (targetWeekday - current + 7) % 7
        return delta == 0 ? 7 : delta
    }

    func isSearchSelection(_ selection: TaskSelection) -> Bool {
        if case .search = selection {
            return true
        }
        return false
    }

    func searchSubtitle(selection: TaskSelection) -> String? {
        guard case .search(let query) = selection else { return nil }
        return query.isEmpty ? "No results for your search." : "No results for \"\(query)\""
    }

    var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    var isRenamePresented: Binding<Bool> {
        Binding(
            get: { renameTask != nil },
            set: { newValue in
                if !newValue { renameTask = nil }
            }
        )
    }

    var isDeletePresented: Binding<Bool> {
        Binding(
            get: { deleteTask != nil },
            set: { newValue in
                if !newValue { deleteTask = nil }
            }
        )
    }

    var isNewTaskPresented: Binding<Bool> {
        Binding(
            get: { viewModel.newTaskDraft != nil },
            set: { newValue in
                if !newValue { viewModel.cancelNewTask() }
            }
        )
    }
}
