import SwiftUI

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
    let groups: [TaskGroup]
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
        buildListOptions(groups: groups, projects: projects)
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
