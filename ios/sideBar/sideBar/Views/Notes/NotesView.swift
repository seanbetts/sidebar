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
    @State private var isRenameDialogPresented = false
    @State private var renameValue: String = ""
    @State private var isMoveSheetPresented = false
    @State private var moveSelection: String = ""
    @State private var isDeleteAlertPresented = false
    @State private var isCloseConfirmPresented = false
    @State private var isExporting = false
    @State private var exportDocument: MarkdownFileDocument?
    @State private var exportFilename: String = "note.md"

    public init() {
    }

    public var body: some View {
        NotesDetailView(
            viewModel: environment.notesRuntime.viewModel,
            editorViewModel: environment.notesRuntime.editorViewModel,
            isRenameDialogPresented: $isRenameDialogPresented,
            renameValue: $renameValue,
            isMoveSheetPresented: $isMoveSheetPresented,
            moveSelection: $moveSelection,
            isDeleteAlertPresented: $isDeleteAlertPresented,
            isCloseConfirmPresented: $isCloseConfirmPresented,
            isExporting: $isExporting,
            exportDocument: $exportDocument,
            exportFilename: $exportFilename
        )
            #if !os(macOS)
            .navigationTitle(noteTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isCompact {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        if environment.notesRuntime.viewModel.activeNote != nil, !isPhone {
                            noteToolbarMenu
                        }
                    }
                }
            }
            #endif
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
                        guard let noteId = environment.notesRuntime.viewModel.activeNote?.path else { return }
                        Task {
                            await environment.notesRuntime.viewModel.moveNote(id: noteId, folder: selection)
                        }
                    }
                )
                .phoneSheetGrabBarVisible()
            }
            .alert("Rename note", isPresented: $isRenameDialogPresented) {
                TextField("Note name", text: $renameValue)
                    .submitLabel(.done)
                    .onSubmit {
                        guard let noteId = environment.notesRuntime.viewModel.activeNote?.path else { return }
                        let updatedName = renameValue
                        isRenameDialogPresented = false
                        renameValue = ""
                        Task {
                            await environment.notesRuntime.viewModel.renameNote(id: noteId, newName: updatedName)
                        }
                    }
                Button("Rename") {
                    guard let noteId = environment.notesRuntime.viewModel.activeNote?.path else { return }
                    let updatedName = renameValue
                    isRenameDialogPresented = false
                    renameValue = ""
                    Task {
                        await environment.notesRuntime.viewModel.renameNote(id: noteId, newName: updatedName)
                    }
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {
                    renameValue = ""
                }
            }
            .deleteConfirmationAlert(
                title: "Delete note",
                isPresented: $isDeleteAlertPresented,
                message: "This will remove the note and cannot be undone.",
                confirmAsDefaultAction: true,
                onConfirm: {
                    guard let noteId = environment.notesRuntime.viewModel.activeNote?.path else { return }
                    Task {
                        await deleteNoteAfterDismissal(id: noteId)
                    }
                },
                onCancel: { }
            )
            .confirmationDialog("Save changes?", isPresented: $isCloseConfirmPresented, titleVisibility: .visible) {
                Button("Save changes") {
                    Task {
                        await environment.notesRuntime.editorViewModel.saveIfNeeded()
                        environment.notesRuntime.viewModel.clearSelection()
                    }
                }
                Button("Don't save", role: .destructive) {
                    environment.notesRuntime.viewModel.clearSelection()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You have unsaved changes. Save before closing the note?")
            }
    }

    private var noteTitle: String {
        #if os(macOS)
        return "Notes"
        #else
        guard horizontalSizeClass == .compact else {
            return "Notes"
        }
        guard let name = environment.notesRuntime.viewModel.activeNote?.name else {
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

    #if os(iOS)
    private var noteToolbarMenu: some View {
        HeaderActionMenuButton(
            systemImage: "ellipsis",
            accessibilityLabel: "Note options",
            items: [
                .pin(isPinned: isPinned) {
                    guard let noteId = environment.notesRuntime.viewModel.activeNote?.path else { return }
                    Task {
                        await environment.notesRuntime.viewModel.setPinned(id: noteId, pinned: !isPinned)
                    }
                },
                .rename {
                    renameValue = displayTitle
                    isRenameDialogPresented = true
                },
                .move {
                    moveSelection = currentFolderPath
                    isMoveSheetPresented = true
                },
                .copyMarkdown {
                    copyMarkdown()
                },
                .shareText {
                    shareMarkdown()
                },
                .download {
                    exportMarkdown()
                },
                .archive(isArchived: isArchived) {
                    archiveActiveNote()
                },
                .delete {
                    isDeleteAlertPresented = true
                }
            ],
            isCompact: isCompact
        )
    }

    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }
    #endif

    private var displayTitle: String {
        guard let name = environment.notesRuntime.viewModel.activeNote?.name else {
            return "Notes"
        }
        if name.hasSuffix(".md") {
            return String(name.dropLast(3))
        }
        return name
    }

    private var activeNode: FileNode? {
        guard let noteId = environment.notesRuntime.viewModel.activeNote?.path else { return nil }
        return environment.notesRuntime.viewModel.noteNode(id: noteId)
    }

    private var isPinned: Bool {
        activeNode?.pinned == true
    }

    private var isArchived: Bool {
        activeNode?.archived == true
    }

    private var currentFolderPath: String {
        guard let path = activeNode?.path else { return "" }
        guard let lastSlash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<lastSlash])
    }

    private var folderOptions: [FolderOption] {
        FolderOption.build(from: environment.notesRuntime.viewModel.tree?.children ?? [])
    }

    private func copyMarkdown() {
        let text = environment.notesRuntime.editorViewModel.content.isEmpty
            ? environment.notesRuntime.viewModel.activeNote?.content ?? ""
            : environment.notesRuntime.editorViewModel.content
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
        let text = environment.notesRuntime.editorViewModel.content.isEmpty
            ? environment.notesRuntime.viewModel.activeNote?.content ?? ""
            : environment.notesRuntime.editorViewModel.content
        guard let name = environment.notesRuntime.viewModel.activeNote?.name else { return }
        let filename = name.hasSuffix(".md") ? name : "\(name).md"
        exportFilename = filename
        exportDocument = MarkdownFileDocument(text: text)
        isExporting = true
    }

    private func shareMarkdown() {
        let text = environment.notesRuntime.editorViewModel.content.isEmpty
            ? environment.notesRuntime.viewModel.activeNote?.content ?? ""
            : environment.notesRuntime.editorViewModel.content
        guard !text.isEmpty else { return }
        SystemSharePresenter.share(text: text)
    }

    private func archiveActiveNote() {
        guard let noteId = environment.notesRuntime.viewModel.activeNote?.path else { return }
        Task {
            await environment.notesRuntime.viewModel.setArchived(id: noteId, archived: !isArchived)
        }
    }

    private func deleteNoteAfterDismissal(id: String) async {
        prepareForDestructiveAction()
        await waitForKeyboardDismissal()
        await environment.notesRuntime.viewModel.deleteNote(id: id)
    }

    private func prepareForDestructiveAction() {
        environment.notesRuntime.editorViewModel.setReadOnly(true)
        #if os(iOS)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        #endif
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
