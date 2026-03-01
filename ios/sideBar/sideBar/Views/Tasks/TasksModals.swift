import SwiftUI

enum RepeatType: String, CaseIterable {
    case none
    case daily
    case weekly
    case monthly
}

func canSaveRenamedTaskTitle(originalTitle: String, editedTitle: String) -> Bool {
    let trimmedTitle = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmedTitle.isEmpty && trimmedTitle != originalTitle
}

struct RenameTaskSheet: View {
    let task: TaskItem
    let onSave: (String) -> Void
    let onDismiss: () -> Void

    @State private var title: String = ""
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Task name") {
                    TextField("Task title", text: $title, axis: .vertical)
                        .lineLimit(1...3)
                        .textInputAutocapitalizationSentences()
                        .disableAutocorrection(false)
                        .focused($isTitleFocused)
                        .submitLabelDone()
                        .onSubmit { handleSave() }
                }
            }
            .navigationTitle("Rename task")
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        handleSave()
                    }
                    .disabled(!canSaveRenamedTaskTitle(originalTitle: task.title, editedTitle: title))
                }
            }
            .onAppear {
                title = task.title
                isTitleFocused = true
            }
        }
    }

    private func handleSave() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSaveRenamedTaskTitle(originalTitle: task.title, editedTitle: title) else { return }
        onSave(trimmedTitle)
        onDismiss()
    }
}

struct NewTaskSheet: View {
    let draft: TaskDraft
    let groups: [TaskGroup]
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
                        #if os(macOS)
                        .textFieldStyle(.roundedBorder)
                        #endif
                        .textInputAutocapitalizationSentences()
                        .disableAutocorrection(false)
                        .focused($focusedField, equals: .title)
                        .submitLabelDone()
                        .onSubmit { handleSave() }
                }

                Section {
                    HStack {
                        if hasDueDate {
                            DatePicker("Due date", selection: $dueDate, displayedComponents: .date)
                                .appFont(.body)
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
                    .appFont(.body)
                    #if os(macOS)
                    .pickerStyle(.menu)
                    #endif
                    .frame(minHeight: 44)
                } header: {
                    Text("Details")
                }

                Section("Notes") {
                    ZStack(alignment: .topLeading) {
                        if notes.isEmpty {
                            Text("Notes (optional)")
                                .appFont(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                        }
                        TextEditor(text: $notes)
                            .frame(minHeight: 120)
                            #if os(macOS)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, DesignTokens.Spacing.xxs)
                            .padding(.vertical, DesignTokens.Spacing.xxsPlus)
                            .background(DesignTokens.Colors.surface)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: DesignTokens.Radius.sm,
                                    style: .continuous
                                )
                            )
                            .overlay(
                                RoundedRectangle(
                                    cornerRadius: DesignTokens.Radius.sm,
                                    style: .continuous
                                )
                                .stroke(DesignTokens.Colors.border, lineWidth: 1)
                            )
                            #endif
                    }
                }

                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .appFont(.caption)
                            .foregroundStyle(DesignTokens.Colors.error)
                    }
                }
            }
            .navigationTitle("New task")
            .navigationBarTitleDisplayModeInline()
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
        #if os(macOS)
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(DesignTokens.Colors.background)
        .presentationBackground(DesignTokens.Colors.background)
        .presentationSizing(.fitted)
        .frame(minWidth: 500, idealWidth: 560, maxWidth: 640, minHeight: 500)
        #endif
    }

    private var listOptions: [TaskListOption] {
        buildListOptions(groups: groups, projects: projects)
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
                        .textInputAutocapitalizationSentences()
                        .disableAutocorrection(false)
                        .focused($isTitleFocused)
                        .submitLabelDone()
                        .onSubmit { handleSave() }
                }

                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .appFont(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New group")
            .navigationBarTitleDisplayModeInline()
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
    let groups: [TaskGroup]
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
                        .textInputAutocapitalizationSentences()
                        .disableAutocorrection(false)
                        .focused($isTitleFocused)
                        .submitLabelDone()
                        .onSubmit { handleSave() }
                }

                Section("Group") {
                    Picker("Group", selection: $groupId) {
                        Text("No group").tag("")
                        ForEach(groupsSorted, id: \.id) { group in
                            Text(group.title).tag(group.id)
                        }
                    }
                    .appFont(.body)
                }

                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .appFont(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New project")
            .navigationBarTitleDisplayModeInline()
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

    private var groupsSorted: [TaskGroup] {
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
