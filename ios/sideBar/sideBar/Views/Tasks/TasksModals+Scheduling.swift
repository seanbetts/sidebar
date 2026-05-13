import SwiftUI
import sideBarShared

struct DueDateSheet: View {
    let task: TaskItem
    let dueDate: Date
    let onSave: (Date?) -> Void
    let onClear: () -> Void
    let onDismiss: () -> Void

    @State private var selectedDate: Date = Date()

    var body: some View {
        let content = NavigationStack {
            Form {
                Section("Due date") {
                    HStack {
                        DatePicker("Due date", selection: $selectedDate, displayedComponents: .date)
                            .appFont(.body)
                            .datePickerStyle(.compact)
                        Spacer()
                        Button {
                            onClear()
                            onDismiss()
                        } label: {
                            Image(appIcon: AppIcon.Action.clearFilled)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear due date")
                    }
                }
            }
            .navigationTitle("Due date")
            .navigationBarTitleDisplayModeInline()
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
        #if os(macOS)
        MacModalShell(type: .compactSheet) {
            content
        }
        #else
        content
        #endif
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
    @State private var searchQuery: String = ""

    var body: some View {
        #if os(macOS)
        MacModalShell(type: .chooserSheet) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text("Move task")
                        .appFont(.titleMd)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text("Choose where \(task.title) should live.")
                        .appFont(.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .lineLimit(2)
                }

                if showsSearch {
                    SearchField(
                        text: $searchQuery,
                        placeholder: "Search destinations"
                    )
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                        ForEach(filteredSections) { section in
                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                                Text(section.title)
                                    .appFont(.caption)
                                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                                VStack(spacing: DesignTokens.Spacing.xxs) {
                                    ForEach(section.destinations) { destination in
                                        moveDestinationRow(destination)
                                    }
                                }
                            }
                        }
                    }
                }

                HStack(spacing: DesignTokens.Spacing.sm) {
                    Spacer()
                    Button("Cancel") {
                        onDismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("Move") {
                        let value = selectedId.isEmpty ? nil : selectedId
                        onSave(value)
                        onDismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(DesignTokens.Spacing.lg)
            .frame(minHeight: 360, idealHeight: 420)
            .onAppear { selectedId = selectedListId }
        }
        #else
        NavigationStack {
            Form {
                Section("Move to") {
                    Picker("Group or project", selection: $selectedId) {
                        Text("No group").tag("")
                        ForEach(listOptions, id: \.id) { option in
                            Text(option.label).tag(option.id)
                        }
                    }
                    .appFont(.body)
                }
            }
            .navigationTitle("Move task")
            .navigationBarTitleDisplayModeInline()
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
        #endif
    }

    private var listOptions: [TaskListOption] {
        buildListOptions(groups: groups, projects: projects)
    }

    private var moveSections: [MoveTaskSection] {
        buildMoveTaskSections(groups: groups, projects: projects)
    }

    private var filteredSections: [MoveTaskSection] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return moveSections }

        return moveSections.compactMap { section in
            let destinations = section.destinations.filter {
                $0.label.localizedCaseInsensitiveContains(query)
            }
            guard !destinations.isEmpty else { return nil }
            return MoveTaskSection(id: section.id, title: section.title, destinations: destinations)
        }
    }

    private var showsSearch: Bool {
        moveSections.reduce(into: 0) { partialResult, section in
            partialResult += section.destinations.count
        } > 8
    }

    @ViewBuilder
    private func moveDestinationRow(_ destination: MoveTaskDestination) -> some View {
        Button {
            selectedId = destination.id
        } label: {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Text(destination.label)
                    .appFont(.body)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if selectedId == destination.id {
                    Image(appIcon: AppIcon.State.success)
                        .appFont(.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                    .fill(selectedId == destination.id ? DesignTokens.Colors.muted : DesignTokens.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                    .stroke(DesignTokens.Colors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
        let content = NavigationStack {
            Form {
                Section("Repeat") {
                    Picker("Repeat", selection: $selectedType) {
                        Text("None").tag(RepeatType.none)
                        Text("Daily").tag(RepeatType.daily)
                        Text("Weekly").tag(RepeatType.weekly)
                        Text("Monthly").tag(RepeatType.monthly)
                    }
                    .appFont(.body)
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
                            .appFont(.body)
                            .datePickerStyle(.compact)
                        if selectedType == .weekly {
                            Text("On \(weekdayLabel(for: startDateValue))")
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if selectedType == .monthly {
                            Text("On day \(Calendar.current.component(.day, from: startDateValue))")
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Repeat")
            .navigationBarTitleDisplayModeInline()
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
        #if os(macOS)
        MacModalShell(type: .compactSheet) {
            content
        }
        #else
        content
        #endif
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
