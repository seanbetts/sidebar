import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

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
    @StateObject private var editorHandle = CodeMirrorEditorHandle()
    @State private var isRenameDialogPresented = false
    @State private var renameValue: String = ""
    @State private var isMoveSheetPresented = false
    @State private var moveSelection: String = ""
    @State private var isDeleteAlertPresented = false
    @State private var isArchiveAlertPresented = false
    @State private var isExporting = false
    @State private var exportDocument: MarkdownFileDocument?
    @State private var exportFilename: String = "note.md"
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        VStack(spacing: 0) {
            if environment.isOffline {
                OfflineBanner()
            }
            if !isCompact {
                header
                Divider()
            }
            contentWithToolbar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                editorViewModel.isEditing = false
                Task {
                    await viewModel.deleteNote(id: noteId)
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
                editorViewModel.isEditing = false
                Task {
                    await viewModel.setArchived(id: noteId, archived: !isArchived)
                }
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(archiveAlertMessage)
        }
        .toolbar {
            if isCompact, viewModel.activeNote != nil {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    noteActionsMenu
                    closeButton
                }
            }
        }
    }

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            ContentHeaderRow(
                iconName: "text.document",
                title: displayTitle
            ) {
                if viewModel.activeNote != nil {
                    SaveStatusView(editorViewModel: editorViewModel)
                    HStack(spacing: 30) {
                        noteActionsMenu
                        closeButton
                    }
                }
            }
            .padding(16)
            .opacity(isEditingToolbarVisible ? 0 : 1)
            .allowsHitTesting(!isEditingToolbarVisible)
            if isEditingToolbarVisible {
                GeometryReader { proxy in
                    Color.platformSecondarySystemBackground
                        .overlay(alignment: .center) {
                            MarkdownFormattingToolbar(isReadOnly: editorViewModel.isReadOnly, onClose: {
                                editorViewModel.isEditing = false
                            }) { command in
                                editorHandle.applyCommand(command)
                            }
                            .background(Color.clear)
                        }
                        .frame(height: proxy.size.height)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: LayoutMetrics.contentHeaderMinHeight)
        .animation(.easeInOut(duration: 0.2), value: editorViewModel.isEditing)
    }

    @ViewBuilder
    private var content: some View {
            if viewModel.activeNote != nil {
                MarkdownEditorView(
                    viewModel: editorViewModel,
                    maxContentWidth: contentMaxWidth,
                    showsCompactStatus: isCompact,
                    editorHandle: editorHandle,
                    isEditing: isEditingBinding,
                    editorFrame: editorFrameBinding
                )
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
        content
            .overlay(alignment: .top) {
                if isCompact && isEditingToolbarVisible {
                    GeometryReader { proxy in
                        Color.platformSecondarySystemBackground
                            .overlay(alignment: .center) {
                                MarkdownFormattingToolbar(
                                    isReadOnly: editorViewModel.isReadOnly,
                                    onClose: {
                                        editorViewModel.isEditing = false
                                    }
                                ) { command in
                                    editorHandle.applyCommand(command)
                                }
                                .background(Color.clear)
                            }
                            .frame(height: min(proxy.size.height, LayoutMetrics.contentHeaderMinHeight))
                            .transition(.opacity)
                            .zIndex(1)
                    }
                    .frame(height: LayoutMetrics.contentHeaderMinHeight)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: editorViewModel.isEditing)
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
            Image(systemName: "ellipsis.circle")
        }
        .buttonStyle(.plain)
        .font(.system(size: 16, weight: .semibold))
        .imageScale(.medium)
        .accessibilityLabel("Note options")
        .disabled(viewModel.activeNote == nil)
    }

    private var closeButton: some View {
        Button {
            editorViewModel.isEditing = false
            viewModel.clearSelection()
        } label: {
            Image(systemName: "xmark")
        }
        .buttonStyle(.plain)
        .font(.system(size: 14, weight: .semibold))
        .imageScale(.medium)
        .accessibilityLabel("Close note")
        .disabled(viewModel.activeNote == nil)
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

    private var isEditingToolbarVisible: Bool {
        editorViewModel.isEditing && !editorViewModel.isReadOnly
    }

    private var isEditingBinding: Binding<Bool> {
        Binding(
            get: { editorViewModel.isEditing },
            set: { editorViewModel.isEditing = $0 }
        )
    }

    private var editorFrameBinding: Binding<CGRect> {
        Binding(
            get: { editorViewModel.editorFrame },
            set: { editorViewModel.editorFrame = $0 }
        )
    }

    private func copyMarkdown() {
        let text = editorViewModel.content.isEmpty ? viewModel.activeNote?.content ?? "" : editorViewModel.content
        guard !text.isEmpty else { return }
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private func exportMarkdown() {
        let text = editorViewModel.content.isEmpty ? viewModel.activeNote?.content ?? "" : editorViewModel.content
        guard let name = viewModel.activeNote?.name else { return }
        let filename = name.hasSuffix(".md") ? name : "\(name).md"
        exportFilename = filename
        exportDocument = MarkdownFileDocument(text: text)
        isExporting = true
    }

}

private struct FolderOption: Identifiable, Hashable {
    let id: String
    let label: String
    let value: String
    let depth: Int

    static func build(from nodes: [FileNode]) -> [FolderOption] {
        var options: [FolderOption] = [
            FolderOption(id: "", label: "Notes", value: "", depth: 0)
        ]

        func walk(_ items: [FileNode], depth: Int) {
            for item in items {
                guard item.type == .directory else { continue }
                if item.name.lowercased() == "archive" { continue }
                let folderPath = item.path.replacingOccurrences(of: "folder:", with: "")
                options.append(
                    FolderOption(
                        id: folderPath,
                        label: item.name,
                        value: folderPath,
                        depth: depth
                    )
                )
                if let children = item.children, !children.isEmpty {
                    walk(children, depth: depth + 1)
                }
            }
        }

        walk(nodes, depth: 1)
        return options
    }
}

private struct NoteFolderPickerSheet: View {
    let title: String
    @Binding var selection: String
    let options: [FolderOption]
    let onConfirm: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(options) { option in
                Button {
                    selection = option.value
                } label: {
                    HStack {
                        Text(optionLabel(option))
                        Spacer()
                        if selection == option.value {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.accent)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") {
                        onConfirm(selection)
                        dismiss()
                    }
                    .disabled(options.isEmpty)
                }
            }
        }
    }

    private func optionLabel(_ option: FolderOption) -> String {
        let indent = String(repeating: "  ", count: max(0, option.depth))
        return indent + option.label
    }
}
