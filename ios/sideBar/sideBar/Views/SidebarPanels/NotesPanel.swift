import Foundation
import SwiftUI
import UniformTypeIdentifiers

public struct NotesPanel: View {
    @EnvironmentObject var environment: AppEnvironment

    public init() {
    }

    public var body: some View {
        NotesPanelView(viewModel: environment.notesViewModel)
    }
}

struct NotesPanelView: View {
    @ObservedObject var viewModel: NotesViewModel
    @EnvironmentObject var environment: AppEnvironment
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif
    @Environment(\.colorScheme) var colorScheme
    @State var hasLoaded = false
    @State var isArchiveExpanded = false
    @State var isNewNotePresented = false
    @State var isNewFolderPresented = false
    @State var newNoteName: String = ""
    @State var newFolderName: String = ""
    @State var newFolderParent: String = ""
    @State var isCreatingNote = false
    @State var isCreatingFolder = false
    @State var renameTarget: FileNodeItem?
    @State var renameValue: String = ""
    @State var deleteTarget: FileNodeItem?
    @State var pendingNoteId: String?
    @State var isSaveChangesDialogPresented = false
    @FocusState var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            #if os(macOS)
            notesPanelContentWithArchive
            #else
            notesPanelContent
            #endif
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            if !hasLoaded {
                hasLoaded = true
                Task { await viewModel.loadTree() }
            }
        }
        .onChange(of: viewModel.searchQuery) { _, newValue in
            viewModel.updateSearch(query: newValue)
        }
        .alert("New Note", isPresented: $isNewNotePresented) {
            TextField("Note title", text: $newNoteName)
                .submitLabel(.done)
                .onSubmit {
                    createNote()
                }
            Button("Create") {
                createNote()
            }
            .disabled(isCreatingNote || newNoteName.trimmed.isEmpty)
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {
                newNoteName = ""
            }
        }
        .sheet(isPresented: $isNewFolderPresented) {
            NewFolderSheet(
                name: $newFolderName,
                selectedFolder: $newFolderParent,
                options: folderOptions,
                isSaving: isCreatingFolder,
                onCreate: createFolder
            )
        }
        .alert(renameDialogTitle, isPresented: isRenameDialogPresented) {
            TextField(renameDialogPlaceholder, text: $renameValue)
                .submitLabel(.done)
                .onSubmit {
                    commitRename()
                }
            Button("Rename") {
                commitRename()
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {
                renameTarget = nil
                renameValue = ""
            }
        }
        .alert(deleteDialogTitle, isPresented: isDeleteDialogPresented) {
            Button("Delete", role: .destructive) {
                let target = deleteTarget
                deleteTarget = nil
                Task {
                    if let target {
                        if target.isFile {
                            await viewModel.deleteNote(id: target.id)
                        } else {
                            await viewModel.deleteFolder(path: target.id)
                        }
                    }
                }
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {
                deleteTarget = nil
            }
        } message: {
            Text(deleteDialogMessage)
        }
        .confirmationDialog("Save changes?", isPresented: $isSaveChangesDialogPresented, titleVisibility: .visible) {
            Button("Save changes") {
                confirmSaveAndSwitch()
            }
            Button("Don't save", role: .destructive) {
                discardAndSwitch()
            }
            Button("Cancel", role: .cancel) {
                pendingNoteId = nil
            }
        } message: {
            Text("You have unsaved changes. Save before switching notes?")
        }
        .onReceive(environment.$shortcutActionEvent) { event in
            guard let event, event.section == .notes else { return }
            switch event.action {
            case .focusSearch:
                isSearchFocused = true
            case .newItem:
                newNoteName = ""
                isNewNotePresented = true
            case .createFolder:
                newFolderName = ""
                newFolderParent = ""
                isNewFolderPresented = true
            case .navigateList(let direction):
                navigateNotesList(direction: direction)
            default:
                break
            }
        }
    }

}
