import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - NotesView

public struct NotesView: View {
    @EnvironmentObject private var environment: AppEnvironment
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    public init() {
    }

    public var body: some View {
        NotesDetailView(
            viewModel: environment.notesViewModel,
            editorViewModel: environment.notesEditorViewModel
        )
            #if !os(macOS)
            .navigationTitle(noteTitle)
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }

    private var noteTitle: String {
        #if os(macOS)
        return "Notes"
        #else
        guard horizontalSizeClass == .compact else {
            return "Notes"
        }
        guard let name = environment.notesViewModel.activeNote?.name else {
            return "Notes"
        }
        if name.hasSuffix(".md") {
            return String(name.dropLast(3))
        }
        return name
        #endif
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }
}

private struct NotesDetailView: View {
    @ObservedObject var viewModel: NotesViewModel
    @ObservedObject var editorViewModel: NotesEditorViewModel
    private let contentMaxWidth: CGFloat = SideBarMarkdownLayout.maxContentWidth
    @EnvironmentObject private var environment: AppEnvironment
    @State private var isRenameDialogPresented = false
    @State private var renameValue: String = ""
    @State private var isMoveSheetPresented = false
    @State private var moveSelection: String = ""
    @State private var isDeleteAlertPresented = false
    @State private var isArchiveAlertPresented = false
    @State private var isActionsDialogPresented = false
    @State private var isCloseConfirmPresented = false
    @State private var isExporting = false
    @State private var exportDocument: MarkdownFileDocument?
    @State private var exportFilename: String = "note.md"
    @State private var showSavedIndicator = false
    @State private var lastSavedTimestamp: TimeInterval = 0
    @State private var savedIndicatorTask: Task<Void, Never>?
    @AppStorage(AppStorageKeys.useNativeMarkdownEditor) private var useNativeMarkdownEditor = true
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        VStack(spacing: 0) {
            OfflineBanner()
            if !isCompact {
                header
                Divider()
            }
            contentWithToolbar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: editorViewModel.lastSavedAt) { _, newValue in
            handleSavedIndicatorChange(newValue)
        }
        .onChange(of: editorViewModel.isDirty) { _, isDirty in
            if isDirty {
                hideSavedIndicator()
            }
        }
        .onChange(of: editorViewModel.isSaving) { _, isSaving in
            if isSaving {
                hideSavedIndicator()
            }
        }
        .onChange(of: editorViewModel.currentNoteId) { _, _ in
            resetSavedIndicator()
        }
        .onDisappear {
            savedIndicatorTask?.cancel()
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .sideBarMarkdown,
            defaultFilename: exportFilename
        ) { _ in
            exportDocument = nil
        }
        .sheet(isPresented: $isMoveSheetPresented) {
            NoteFolderPickerSheet(
                title: "Move Note",
                selection: $moveSelection,
                options: folderOptions,
                onConfirm: { selection in
                    guard let noteId = viewModel.activeNote?.path else { return }
                    Task {
                        await viewModel.moveNote(id: noteId, folder: selection)
                    }
                }
            )
        }
        .alert("Rename note", isPresented: $isRenameDialogPresented) {
            TextField("Note name", text: $renameValue)
                .submitLabel(.done)
                .onSubmit {
                    guard let noteId = viewModel.activeNote?.path else { return }
                    let updatedName = renameValue
                    isRenameDialogPresented = false
                    renameValue = ""
                    Task {
                        await viewModel.renameNote(id: noteId, newName: updatedName)
                    }
                }
            Button("Rename") {
                guard let noteId = viewModel.activeNote?.path else { return }
                let updatedName = renameValue
                isRenameDialogPresented = false
                renameValue = ""
                Task {
                    await viewModel.renameNote(id: noteId, newName: updatedName)
                }
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {
                renameValue = ""
            }
        }
        .alert("Delete note", isPresented: $isDeleteAlertPresented) {
            Button("Delete", role: .destructive) {
                guard let noteId = viewModel.activeNote?.path else { return }
                Task {
                    await deleteNoteAfterDismissal(id: noteId)
                }
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove the note and cannot be undone.")
        }
        .alert(archiveAlertTitle, isPresented: $isArchiveAlertPresented) {
            Button(archiveActionTitle, role: .destructive) {
                guard let noteId = viewModel.activeNote?.path else { return }
                Task {
                    await viewModel.setArchived(id: noteId, archived: !isArchived)
                }
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(archiveAlertMessage)
        }
        .confirmationDialog("Note actions", isPresented: $isActionsDialogPresented, titleVisibility: .visible) {
            Button(pinActionTitle) {
                guard let noteId = viewModel.activeNote?.path else { return }
                Task {
                    await viewModel.setPinned(id: noteId, pinned: !isPinned)
                }
            }
            Button("Rename") {
                renameValue = displayTitle
                isRenameDialogPresented = true
            }
            Button("Move") {
                moveSelection = currentFolderPath
                isMoveSheetPresented = true
            }
            Button("Copy") {
                copyMarkdown()
            }
            Button("Download") {
                exportMarkdown()
            }
            Button(archiveMenuTitle) {
                isArchiveAlertPresented = true
            }
            Button("Delete", role: .destructive) {
                isDeleteAlertPresented = true
            }
            Button("Cancel", role: .cancel) { }
        }
        .confirmationDialog("Save changes?", isPresented: $isCloseConfirmPresented, titleVisibility: .visible) {
            Button("Save changes") {
                Task {
                    await editorViewModel.saveIfNeeded()
                    viewModel.clearSelection()
                }
            }
            Button("Don't save", role: .destructive) {
                viewModel.clearSelection()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You have unsaved changes. Save before closing the note?")
        }
        .onReceive(environment.$shortcutActionEvent) { event in
            guard let event, event.section == .notes else { return }
            switch event.action {
            case .closeItem:
                requestCloseNote()
            case .renameItem:
                guard viewModel.activeNote != nil else { return }
                renameValue = displayTitle
                isRenameDialogPresented = true
            case .deleteItem:
                guard viewModel.activeNote != nil else { return }
                isDeleteAlertPresented = true
            case .archiveItem:
                guard viewModel.activeNote != nil else { return }
                isArchiveAlertPresented = true
            default:
                break
            }
        }
        .toolbar {
            if isCompact, viewModel.activeNote != nil {
                #if os(iOS)
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    noteActionsMenu
                    closeButton
                }
                #endif
            }
        }
    }

    private func prepareForDestructiveAction() {
        editorViewModel.setReadOnly(true)
        #if os(iOS)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        #endif
    }

    private func deleteNoteAfterDismissal(id: String) async {
        prepareForDestructiveAction()
        await waitForKeyboardDismissal()
        await viewModel.deleteNote(id: id)
    }

    private func openActionsDialog() async {
        prepareForDestructiveAction()
        await waitForKeyboardDismissal()
        isActionsDialogPresented = true
    }

    @MainActor
    private func waitForKeyboardDismissal(timeout: UInt64 = 500_000_000) async {
        #if os(iOS)
        let notifications = NotificationCenter.default.notifications(named: UIResponder.keyboardDidHideNotification)
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await _ in notifications {
                    break
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeout)
            }
            await group.next()
            group.cancelAll()
        }
        #endif
    }
}

extension NotesDetailView {
    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            ContentHeaderRow(
                iconName: "text.document",
                title: displayTitle
            ) {
                if viewModel.activeNote != nil {
                    HStack(spacing: DesignTokens.Spacing.md) {
                        if let status = noteStatus {
                            noteStatusText(status)
                        }
                        HeaderActionRow {
                            noteActionsMenu
                            closeButton
                        }
                    }
                }
            }
            .padding(DesignTokens.Spacing.md)
        }
        .frame(maxWidth: .infinity)
        .frame(height: LayoutMetrics.contentHeaderMinHeight)
    }

    @ViewBuilder
    private var content: some View {
            if viewModel.activeNote != nil {
                if #available(iOS 26.0, macOS 26.0, *), useNativeMarkdownEditor {
                    NativeMarkdownEditorContainer(
                        editorViewModel: editorViewModel,
                        maxContentWidth: contentMaxWidth
                    )
                } else {
                    SideBarMarkdownContainer(text: editorViewModel.content)
                        .onAppear {
                            editorViewModel.setReadOnly(true)
                        }
                }
            } else if viewModel.selectedNoteId != nil {
                if let error = viewModel.errorMessage {
                    PlaceholderView(
                        title: "Unable to load note",
                        subtitle: error,
                        actionTitle: "Retry"
                    ) {
                        guard let selectedId = viewModel.selectedNoteId else { return }
                        Task { await viewModel.loadNote(id: selectedId) }
                    }
                } else {
                    LoadingView(message: "Loading note…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                #if os(macOS)
                if viewModel.tree == nil {
                    LoadingView(message: "Loading notes…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    WelcomeEmptyView()
                }
                #else
                if viewModel.tree == nil {
                    LoadingView(message: "Loading notes…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    PlaceholderView(
                        title: "Select a note",
                        subtitle: "Choose a note from the sidebar to start reading.",
                        iconName: "text.document"
                    )
                }
                #endif
            }
        }

    private var contentWithToolbar: some View {
        VStack(spacing: 0) {
            if isCompact, viewModel.activeNote != nil, let status = noteStatus {
                HStack {
                    Spacer()
                    noteStatusText(status)
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.xs)
                Divider()
            }
            content
        }
    }

    private struct NoteStatus: Equatable {
        let text: String
        let color: Color
    }

    private var noteStatus: NoteStatus? {
        if editorViewModel.isReadOnly {
            return NoteStatus(text: "Read-only preview", color: DesignTokens.Colors.textSecondary)
        }
        if let error = editorViewModel.saveErrorMessage, !error.isEmpty {
            return NoteStatus(text: error, color: DesignTokens.Colors.error)
        }
        if editorViewModel.isSaving {
            return NoteStatus(text: "Saving...", color: DesignTokens.Colors.textSecondary)
        }
        if editorViewModel.isDirty {
            return NoteStatus(text: "Unsaved changes", color: DesignTokens.Colors.textSecondary)
        }
        if let label = lastSavedLabel {
            return NoteStatus(text: "Saved \(label)", color: DesignTokens.Colors.textSecondary)
        }
        return nil
    }

    private var lastSavedLabel: String? {
        guard showSavedIndicator, let lastSaved = editorViewModel.lastSavedAt else { return nil }
        return formatLastSaved(lastSaved)
    }

    private func noteStatusText(_ status: NoteStatus) -> some View {
        Text(status.text)
            .font(.caption)
            .foregroundStyle(status.color)
            .lineLimit(1)
    }

    private func formatLastSaved(_ date: Date) -> String {
        let now = Date()
        let diffSeconds = Int(now.timeIntervalSince(date))
        if diffSeconds < 60 {
            return "just now"
        }
        if diffSeconds < 3600 {
            return "\(diffSeconds / 60)m ago"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func handleSavedIndicatorChange(_ date: Date?) {
        guard let date else { return }
        let timestamp = date.timeIntervalSince1970
        guard timestamp != lastSavedTimestamp else { return }
        lastSavedTimestamp = timestamp
        guard !editorViewModel.isDirty, !editorViewModel.isSaving else { return }
        showSavedIndicator = true
        savedIndicatorTask?.cancel()
        savedIndicatorTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            showSavedIndicator = false
        }
    }

    private func hideSavedIndicator() {
        showSavedIndicator = false
        savedIndicatorTask?.cancel()
        savedIndicatorTask = nil
    }

    private func resetSavedIndicator() {
        hideSavedIndicator()
        lastSavedTimestamp = 0
    }

    private var displayTitle: String {
        guard let name = viewModel.activeNote?.name else {
            return "Notes"
        }
        if name.hasSuffix(".md") {
            return String(name.dropLast(3))
        }
        return name
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    private var noteActionsMenu: some View {
        #if os(macOS)
        Menu {
            Button {
                guard let noteId = viewModel.activeNote?.path else { return }
                Task {
                    await viewModel.setPinned(id: noteId, pinned: !isPinned)
                }
            } label: {
                Label(pinActionTitle, systemImage: pinIconName)
            }
            Button {
                renameValue = displayTitle
                isRenameDialogPresented = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                moveSelection = currentFolderPath
                isMoveSheetPresented = true
            } label: {
                Label("Move", systemImage: "arrow.forward.folder")
            }
            Button {
                copyMarkdown()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            Button {
                exportMarkdown()
            } label: {
                Label("Download", systemImage: "square.and.arrow.down")
            }
            Button {
                isArchiveAlertPresented = true
            } label: {
                Label(archiveMenuTitle, systemImage: archiveIconName)
            }
            Button(role: .destructive) {
                isDeleteAlertPresented = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            HeaderActionIcon(systemName: "ellipsis.circle")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Note options")
        .disabled(viewModel.activeNote == nil)
        #else
        Button {
            Task { await openActionsDialog() }
        } label: {
            HeaderActionIcon(systemName: "ellipsis.circle")
        }
        .buttonStyle(.plain)
        .frame(width: 28, height: 20)
        .accessibilityLabel("Note options")
        .disabled(viewModel.activeNote == nil)
        #endif
    }

    private var closeButton: some View {
        HeaderActionButton(
            systemName: "xmark",
            accessibilityLabel: "Close note",
            action: {
                requestCloseNote()
            },
            isDisabled: viewModel.activeNote == nil
        )
    }

    private var activeNode: FileNode? {
        guard let noteId = viewModel.activeNote?.path else { return nil }
        return viewModel.noteNode(id: noteId)
    }

    private var isPinned: Bool {
        activeNode?.pinned == true
    }

    private var isArchived: Bool {
        activeNode?.archived == true
    }

    private var pinActionTitle: String {
        isPinned ? "Unpin" : "Pin"
    }

    private var pinIconName: String {
        isPinned ? "pin.slash" : "pin"
    }

    private var archiveMenuTitle: String {
        isArchived ? "Unarchive" : "Archive"
    }

    private var archiveIconName: String {
        isArchived ? "archivebox.fill" : "archivebox"
    }

    private var archiveActionTitle: String {
        isArchived ? "Unarchive" : "Archive"
    }

    private var archiveAlertTitle: String {
        isArchived ? "Unarchive note" : "Archive note"
    }

    private var archiveAlertMessage: String {
        isArchived
            ? "This will move the note back to your main list."
            : "This will move the note into your archive."
    }

    private var currentFolderPath: String {
        guard let path = activeNode?.path else { return "" }
        guard let lastSlash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<lastSlash])
    }

    private var folderOptions: [FolderOption] {
        FolderOption.build(from: viewModel.tree?.children ?? [])
    }

    private func copyMarkdown() {
        let text = editorViewModel.content.isEmpty ? viewModel.activeNote?.content ?? "" : editorViewModel.content
        guard !text.isEmpty else { return }
        #if os(iOS)
        let pasteboard = UIPasteboard.general
        pasteboard.string = text
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            #if os(macOS)
            let pasteboard = NSPasteboard.general
            if pasteboard.string(forType: .string) == text {
                pasteboard.clearContents()
            }
            #else
            let pasteboard = UIPasteboard.general
            if pasteboard.string == text {
                pasteboard.string = ""
            }
            #endif
        }
    }

    private func exportMarkdown() {
        let text = editorViewModel.content.isEmpty ? viewModel.activeNote?.content ?? "" : editorViewModel.content
        guard let name = viewModel.activeNote?.name else { return }
        let filename = name.hasSuffix(".md") ? name : "\(name).md"
        exportFilename = filename
        exportDocument = MarkdownFileDocument(text: text)
        isExporting = true
    }

    private func requestCloseNote() {
        if editorViewModel.isDirty {
            isCloseConfirmPresented = true
            return
        }
        viewModel.clearSelection()
    }

}
