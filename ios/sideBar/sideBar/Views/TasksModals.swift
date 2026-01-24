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
                    ZStack(alignment: .topLeading) {
                        if value.isEmpty {
                            Text("Notes")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                        }
                        TextEditor(text: $value)
                            .frame(minHeight: 160)
                    }
                }
            }
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
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
                    HStack {
                        DatePicker("Due date", selection: $selectedDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                        Spacer()
                        Button {
                            onClear()
                            onDismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear due date")
                    }
                }
            }
            .navigationTitle("Due date")
            .navigationBarTitleDisplayMode(.inline)
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
                    Picker("Group or project", selection: $selectedId) {
                        Text("No group").tag("")
                        ForEach(listOptions, id: \.id) { option in
                            Text(option.label).tag(option.id)
                        }
                    }
                }
            }
            .navigationTitle("Move task")
            .navigationBarTitleDisplayMode(.inline)
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
                    Picker("Repeat", selection: $selectedType) {
                        Text("None").tag(RepeatType.none)
                        Text("Daily").tag(RepeatType.daily)
                        Text("Weekly").tag(RepeatType.weekly)
                        Text("Monthly").tag(RepeatType.monthly)
                    }
                    .pickerStyle(.segmented)
                    if selectedType != .none {
                        Stepper(value: $intervalValue, in: 1...30) {
                            Text(intervalLabel)
                        }
                    }
                }
                if selectedType != .none {
                    Section("Start date") {
                        DatePicker("Start", selection: $startDateValue, displayedComponents: .date)
                            .datePickerStyle(.compact)
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
            .navigationBarTitleDisplayMode(.inline)
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

    private var intervalLabel: String {
        let unit: String
        switch selectedType {
        case .daily:
            unit = intervalValue == 1 ? "day" : "days"
        case .weekly:
            unit = intervalValue == 1 ? "week" : "weeks"
        case .monthly:
            unit = intervalValue == 1 ? "month" : "months"
        case .none:
            unit = intervalValue == 1 ? "time" : "times"
        }
        return "Every \(intervalValue) \(unit)"
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
    @FocusState private var focusedField: Field?

    private enum Field {
        case title
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Task title", text: $title)
                        .textInputAutocapitalization(.sentences)
                        .disableAutocorrection(false)
                        .focused($focusedField, equals: .title)
                        .submitLabel(.done)
                        .onSubmit { handleSave() }
                }

                Section {
                    HStack {
                        if hasDueDate {
                            DatePicker("Due date", selection: $dueDate, displayedComponents: .date)
                                .datePickerStyle(.compact)
                        } else {
                            Text("Due date")
                                .foregroundStyle(.primary)
                            Spacer()
                            Button("Add") {
                                hasDueDate = true
                                dueDate = Date()
                            }
                            .foregroundStyle(.accent)
                        }
                        if hasDueDate {
                            Button {
                                hasDueDate = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear due date")
                        }
                    }
                    .frame(minHeight: 44)
                    Picker("Group or project", selection: $listId) {
                        Text("Select group or project").tag("")
                        ForEach(listOptions, id: \.id) { option in
                            Text(option.label).tag(option.id)
                        }
                    }
                    .frame(minHeight: 44)
                } header: {
                    Text("Details")
                }

                Section("Notes") {
                    ZStack(alignment: .topLeading) {
                        if notes.isEmpty {
                            Text("Notes (optional)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                        }
                        TextEditor(text: $notes)
                            .frame(minHeight: 120)
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving..." : "Save") {
                        handleSave()
                    }
                    .disabled(
                        isSaving
                            || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || listId.isEmpty
                    )
                }
            }
            .onAppear {
                title = draft.title
                notes = draft.notes
                hasDueDate = draft.dueDate != nil
                dueDate = draft.dueDate ?? Date()
                listId = draft.listId ?? ""
                focusedField = .title
            }
        }
    }

    private var listOptions: [TaskListOption] {
        buildListOptions(areas: areas, projects: projects)
    }

    private func handleSave() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSaving, !trimmedTitle.isEmpty, !listId.isEmpty else { return }
        let listValue = listId.isEmpty ? nil : listId
        let dateValue = hasDueDate ? dueDate : nil
        onSave(trimmedTitle, notes, dateValue, listValue)
    }

}

struct NewGroupSheet: View {
    let onCreate: (String) async throws -> Void
    let onDismiss: () -> Void

    @State private var title: String = ""
    @State private var isSaving: Bool = false
    @State private var errorMessage: String = ""
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Group") {
                    TextField("Group name", text: $title)
                        .textInputAutocapitalization(.sentences)
                        .disableAutocorrection(false)
                        .focused($isTitleFocused)
                        .submitLabel(.done)
                        .onSubmit { handleSave() }
                }

                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving..." : "Save") {
                        handleSave()
                    }
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                isTitleFocused = true
            }
        }
    }

    private func handleSave() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !isSaving else { return }
        isSaving = true
        errorMessage = ""
        Task {
            do {
                try await onCreate(trimmedTitle)
                onDismiss()
            } catch {
                errorMessage = ErrorMapping.message(for: error)
            }
            isSaving = false
        }
    }
}

struct NewProjectSheet: View {
    let groups: [TaskArea]
    let onCreate: (String, String?) async throws -> Void
    let onDismiss: () -> Void

    @State private var title: String = ""
    @State private var groupId: String = ""
    @State private var isSaving: Bool = false
    @State private var errorMessage: String = ""
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Project") {
                    TextField("Project name", text: $title)
                        .textInputAutocapitalization(.sentences)
                        .disableAutocorrection(false)
                        .focused($isTitleFocused)
                        .submitLabel(.done)
                        .onSubmit { handleSave() }
                }

                Section("Group") {
                    Picker("Group", selection: $groupId) {
                        Text("No group").tag("")
                        ForEach(groupsSorted, id: \.id) { group in
                            Text(group.title).tag(group.id)
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
            .navigationTitle("New project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving..." : "Save") {
                        handleSave()
                    }
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                isTitleFocused = true
            }
        }
    }

    private var groupsSorted: [TaskArea] {
        groups.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func handleSave() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !isSaving else { return }
        let selectedGroupId = groupId.isEmpty ? nil : groupId
        isSaving = true
        errorMessage = ""
        Task {
            do {
                try await onCreate(trimmedTitle, selectedGroupId)
                onDismiss()
            } catch {
                errorMessage = ErrorMapping.message(for: error)
            }
            isSaving = false
        }
    }
}

private struct TaskListOption: Identifiable {
    let id: String
    let label: String
}

private func buildListOptions(areas: [TaskArea], projects: [TaskProject]) -> [TaskListOption] {
    let sortedAreas = areas.sorted {
        $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
    }
    let projectsByArea = Dictionary(grouping: projects, by: { $0.areaId ?? "" })
    var options: [TaskListOption] = []

    for area in sortedAreas {
        options.append(TaskListOption(id: area.id, label: area.title))
        let areaProjects = (projectsByArea[area.id] ?? []).sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        for project in areaProjects {
            options.append(TaskListOption(id: project.id, label: "- \(project.title)"))
        }
    }

    let orphanProjects = (projectsByArea[""] ?? []).sorted {
        $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
    }
    for project in orphanProjects {
        options.append(TaskListOption(id: project.id, label: "- \(project.title)"))
    }

    return options
}
