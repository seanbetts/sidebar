import SwiftUI

enum RepeatType: String, CaseIterable {
    case none
    case daily
    case weekly
    case monthly
}

struct NotesSheet: View {
    let task: TaskItem
    let notes: String
    let onSave: (String) -> Void
    let onDismiss: () -> Void

    @State private var value: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Notes") {
                    TextEditor(text: $value)
                        .frame(minHeight: 140)
                }
            }
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(value)
                        onDismiss()
                    }
                }
            }
            .onAppear { value = notes }
        }
    }
}

struct DueDateSheet: View {
    let task: TaskItem
    let dueDate: Date
    let onSave: (Date?) -> Void
    let onClear: () -> Void
    let onDismiss: () -> Void

    @State private var selectedDate: Date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Due date") {
                    DatePicker("", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }
            }
            .navigationTitle("Due date")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(selectedDate)
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Clear due date") {
                        onClear()
                        onDismiss()
                    }
                    .foregroundStyle(.red)
                }
            }
            .onAppear { selectedDate = dueDate }
        }
    }
}

struct MoveTaskSheet: View {
    let task: TaskItem
    let selectedListId: String
    let areas: [TaskArea]
    let projects: [TaskProject]
    let onSave: (String?) -> Void
    let onDismiss: () -> Void

    @State private var selectedId: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Move to") {
                    Picker("", selection: $selectedId) {
                        Text("No list").tag("")
                        ForEach(listOptions, id: \.id) { option in
                            Text(option.label).tag(option.id)
                        }
                    }
                }
            }
            .navigationTitle("Move task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let value = selectedId.isEmpty ? nil : selectedId
                        onSave(value)
                        onDismiss()
                    }
                }
            }
            .onAppear { selectedId = selectedListId }
        }
    }

    private var listOptions: [TaskListOption] {
        buildListOptions(areas: areas, projects: projects)
    }
}

struct RepeatTaskSheet: View {
    let task: TaskItem
    let repeatType: RepeatType
    let interval: Int
    let startDate: Date
    let onSave: (RepeatType, Int, Date) -> Void
    let onDismiss: () -> Void

    @State private var selectedType: RepeatType = .daily
    @State private var intervalValue: Int = 1
    @State private var startDateValue: Date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Repeat") {
                    Picker("", selection: $selectedType) {
                        Text("None").tag(RepeatType.none)
                        Text("Daily").tag(RepeatType.daily)
                        Text("Weekly").tag(RepeatType.weekly)
                        Text("Monthly").tag(RepeatType.monthly)
                    }
                    if selectedType != .none {
                        Stepper(value: $intervalValue, in: 1...30) {
                            Text("Every \(intervalValue) \(intervalValue == 1 ? "time" : "times")")
                        }
                    }
                }
                if selectedType != .none {
                    Section("Start date") {
                        DatePicker("", selection: $startDateValue, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                        if selectedType == .weekly {
                            Text("On \(weekdayLabel(for: startDateValue))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if selectedType == .monthly {
                            Text("On day \(Calendar.current.component(.day, from: startDateValue))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Repeat")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(selectedType, intervalValue, startDateValue)
                        onDismiss()
                    }
                }
            }
            .onAppear {
                selectedType = repeatType
                intervalValue = interval
                startDateValue = startDate
            }
        }
    }

    private func weekdayLabel(for date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide))
    }
}

struct NewTaskSheet: View {
    let draft: TaskDraft
    let areas: [TaskArea]
    let projects: [TaskProject]
    let isSaving: Bool
    let errorMessage: String
    let onSave: (String, String, Date?, String?) -> Void
    let onDismiss: () -> Void

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var dueDate: Date = Date()
    @State private var hasDueDate: Bool = true
    @State private var listId: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Title", text: $title)
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                    Toggle("Has due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due date", selection: $dueDate, displayedComponents: .date)
                    }
                }
                Section("List") {
                    Picker("", selection: $listId) {
                        Text("No list").tag("")
                        ForEach(listOptions, id: \.id) { option in
                            Text(option.label).tag(option.id)
                        }
                    }
                }
                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving..." : "Save") {
                        let listValue = listId.isEmpty ? nil : listId
                        let dateValue = hasDueDate ? dueDate : nil
                        onSave(title, notes, dateValue, listValue)
                    }
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                title = draft.title
                notes = draft.notes
                hasDueDate = draft.dueDate != nil
                dueDate = draft.dueDate ?? Date()
                listId = draft.listId ?? ""
            }
        }
    }

    private var listOptions: [TaskListOption] {
        buildListOptions(areas: areas, projects: projects)
    }
}

private struct TaskListOption: Identifiable {
    let id: String
    let label: String
}

private func buildListOptions(areas: [TaskArea], projects: [TaskProject]) -> [TaskListOption] {
    let areaOptions = areas
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        .map { TaskListOption(id: $0.id, label: "Area: \($0.title)") }
    let projectOptions = projects
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        .map { TaskListOption(id: $0.id, label: "Project: \($0.title)") }
    return areaOptions + projectOptions
}
