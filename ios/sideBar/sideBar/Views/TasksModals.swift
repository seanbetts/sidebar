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
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ZStack(alignment: .topLeading) {
                        if value.isEmpty {
                            Text("Notes")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                        }
                        NotesTextEditor(
                            text: $value,
                            isFocused: Binding(
                                get: { isFocused },
                                set: { isFocused = $0 }
                            ),
                            onSubmit: handleSave
                        )
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
                        handleSave()
                    }
                }
            }
            .onAppear {
                value = notes
                isFocused = true
            }
        }
    }

    private func handleSave() {
        onSave(value)
        onDismiss()
    }
}

#if os(macOS)
import AppKit

private struct NotesTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NotesTextView()
        textView.string = text
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 12)
        textView.textContainer?.lineFragmentPadding = 0
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NotesTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.onSubmit = onSubmit
        if isFocused, nsView.window != nil, nsView.window?.firstResponder != textView {
            nsView.window?.makeFirstResponder(textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: NotesTextEditor

        init(parent: NotesTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.isFocused = textView.window?.firstResponder == textView
        }
    }
}

private final class NotesTextView: NSTextView {
    var onSubmit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let isReturnKey = event.keyCode == 36 || event.keyCode == 76
        if isReturnKey {
            if event.modifierFlags.contains(.shift) {
                insertNewline(nil)
            } else {
                onSubmit?()
            }
            return
        }
        super.keyDown(with: event)
    }
}
#else
import UIKit

private struct NotesTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> NotesTextView {
        let textView = NotesTextView()
        textView.backgroundColor = .clear
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        return textView
    }

    func updateUIView(_ uiView: NotesTextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.onSubmit = onSubmit
        if isFocused, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        let parent: NotesTextEditor

        init(parent: NotesTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFocused = false
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard text == "\n" else { return true }
            if let notesView = textView as? NotesTextView, notesView.allowNextNewline {
                notesView.allowNextNewline = false
                return true
            }
            parent.onSubmit()
            return false
        }
    }
}

private final class NotesTextView: UITextView {
    var onSubmit: (() -> Void)?
    var allowNextNewline: Bool = false

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: "\r", modifierFlags: [], action: #selector(handleReturn)),
            UIKeyCommand(input: "\r", modifierFlags: [.shift], action: #selector(handleShiftReturn))
        ]
    }

    @objc private func handleReturn() {
        onSubmit?()
    }

    @objc private func handleShiftReturn() {
        allowNextNewline = true
        insertText("\n")
    }
}
#endif

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

private struct TaskListOption: Identifiable {
    let id: String
    let label: String
}

private func buildListOptions(groups: [TaskGroup], projects: [TaskProject]) -> [TaskListOption] {
    let sortedGroups = groups.sorted {
        $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
    }
    let projectsByGroup = Dictionary(grouping: projects, by: { $0.groupId ?? "" })
    var options: [TaskListOption] = []

    for group in sortedGroups {
        options.append(TaskListOption(id: group.id, label: group.title))
        let groupProjects = (projectsByGroup[group.id] ?? []).sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        for project in groupProjects {
            options.append(TaskListOption(id: project.id, label: "- \(project.title)"))
        }
    }

    let orphanProjects = (projectsByGroup[""] ?? []).sorted {
        $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
    }
    for project in orphanProjects {
        options.append(TaskListOption(id: project.id, label: "- \(project.title)"))
    }

    return options
}
