import Foundation
import sideBarShared
import SwiftUI

// MARK: - NotesPanel+Helpers

extension NotesPanelView {
    var header: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            PanelHeader(title: "Notes") {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Button {
                        newFolderName = ""
                        newFolderParent = ""
                        isNewFolderPresented = true
                    } label: {
                        Image(systemName: "folder")
                            .font(DesignTokens.Typography.labelMd)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add folder")
                    Button {
                        newNoteName = ""
                        isNewNotePresented = true
                    } label: {
                        Image(systemName: "plus")
                            .font(DesignTokens.Typography.labelMd)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add note")
                    if isCompact {
                        SettingsAvatarButton()
                    }
                }
            }
            SearchField(text: $viewModel.searchQuery, placeholder: "Search notes", isFocused: $isSearchFocused)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.bottom, DesignTokens.Spacing.sm)
        }
        .frame(minHeight: LayoutMetrics.panelHeaderMinHeight)
        .background(panelHeaderBackground(colorScheme))
    }

    var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    var folderOptions: [NotesFolderOption] {
        NotesFolderOption.build(from: viewModel.tree?.children ?? [])
    }

    func createNote() {
        let trimmed = newNoteName.trimmed
        guard !trimmed.isEmpty, !isCreatingNote else { return }
        isCreatingNote = true
        Task {
            let created = await viewModel.createNote(title: trimmed, folder: nil)
            await MainActor.run {
                isCreatingNote = false
                if created != nil {
                    isNewNotePresented = false
                }
            }
        }
    }

    func createBlankNoteFromDeepLink() {
        guard !isCreatingNote else { return }
        isCreatingNote = true
        Task {
            let created = await viewModel.createBlankNote()
            await MainActor.run {
                isCreatingNote = false
                guard created == nil else { return }
                // Fall back to manual naming if auto-creation fails.
                newNoteName = ""
                isNewNotePresented = true
            }
        }
    }

    func createFolder() {
        let trimmed = newFolderName.trimmed
        guard !trimmed.isEmpty, !isCreatingFolder else { return }
        isCreatingFolder = true
        Task {
            let destination = newFolderParent.isEmpty ? trimmed : "\(newFolderParent)/\(trimmed)"
            let created = await viewModel.createFolder(path: destination)
            await MainActor.run {
                isCreatingFolder = false
                if created {
                    isNewFolderPresented = false
                }
            }
        }
    }

    var isRenameDialogPresented: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { isPresented in
                if !isPresented {
                    renameTarget = nil
                    renameValue = ""
                }
            }
        )
    }

    var isDeleteDialogPresented: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { isPresented in
                if !isPresented {
                    deleteTarget = nil
                }
            }
        )
    }

    var renameDialogTitle: String {
        renameTarget?.isFile == true ? "Rename note" : "Rename folder"
    }

    var renameDialogPlaceholder: String {
        renameTarget?.isFile == true ? "Note name" : "Folder name"
    }

    var deleteDialogTitle: String {
        deleteTarget?.isFile == true ? "Delete note" : "Delete folder"
    }

    var deleteDialogMessage: String {
        deleteTarget?.isFile == true
            ? "This will remove the note and cannot be undone."
            : "This will remove the folder and its contents."
    }

    func beginRename(for item: FileNodeItem) {
        renameTarget = item
        renameValue = item.displayName
    }

    func confirmDelete(for item: FileNodeItem) {
        Task { @MainActor in
            prepareForDestructiveAction()
            await waitForKeyboardDismissal()
            deleteTarget = item
        }
    }

    func commitRename() {
        let target = renameTarget
        let updated = renameValue
        renameTarget = nil
        renameValue = ""
        guard let target else { return }
        Task {
            if target.isFile {
                await viewModel.renameNote(id: target.id, newName: updated)
            } else {
                await viewModel.renameFolder(path: target.id, newName: updated)
            }
        }
    }

    func navigateNotesList(direction: ShortcutListDirection) {
        let items = noteNavigationItems()
        guard !items.isEmpty else { return }
        let currentId = viewModel.selectedNoteId
        let nextIndex: Int
        if let currentId, let index = items.firstIndex(of: currentId) {
            nextIndex = direction == .next ? min(items.count - 1, index + 1) : max(0, index - 1)
        } else {
            nextIndex = direction == .next ? 0 : items.count - 1
        }
        let nextId = items[nextIndex]
        requestNoteSelection(id: nextId)
    }

    func requestNoteSelection(id: String) {
        guard viewModel.selectedNoteId != id else { return }
        if environment.notesEditorViewModel.isDirty, viewModel.selectedNoteId != nil {
            if environment.isOffline {
                Task {
                    await environment.notesEditorViewModel.saveIfNeeded()
                    await viewModel.selectNote(id: id)
                }
                return
            }
            pendingNoteId = id
            isSaveChangesDialogPresented = true
            return
        }
        Task { await viewModel.selectNote(id: id) }
    }

    func confirmSaveAndSwitch() {
        guard let pendingId = pendingNoteId else { return }
        pendingNoteId = nil
        isSaveChangesDialogPresented = false
        Task {
            await environment.notesEditorViewModel.saveIfNeeded()
            await viewModel.selectNote(id: pendingId)
        }
    }

    func discardAndSwitch() {
        guard let pendingId = pendingNoteId else { return }
        pendingNoteId = nil
        isSaveChangesDialogPresented = false
        Task { await viewModel.selectNote(id: pendingId) }
    }

    var searchResultsView: some View {
        List {
            Section("Results") {
                if let error = viewModel.errorMessage,
                   !viewModel.searchQuery.trimmed.isEmpty {
                    SidebarPanelPlaceholder(
                        title: "Search failed",
                        subtitle: error,
                        actionTitle: "Retry"
                    ) {
                        viewModel.updateSearch(query: viewModel.searchQuery)
                    }
                } else if viewModel.isSearching {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Searching…")
                            .foregroundStyle(.secondary)
                    }
                } else if viewModel.searchResults.isEmpty {
                    Text("No matching notes.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.searchResults, id: \.path) { node in
                        searchResultRow(for: node)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(panelBackground)
    }

    @ViewBuilder
    private func searchResultRow(for node: FileNode) -> some View {
        let item = FileNodeItem(
            id: node.path,
            name: node.name,
            type: node.type,
            children: nil,
            pinned: node.pinned ?? false,
            archived: node.archived ?? false,
            created: node.created
        )
        NotesTreeRow(
            item: item,
            isSelected: viewModel.selectedNoteId == node.path
        ) {
            requestNoteSelection(id: node.path)
        } onRename: {
            beginRename(for: item)
        } onDelete: {
            confirmDelete(for: item)
        }
        .platformContextMenu(items: noteContextMenuItemsList(for: item))
    }

    var notesPanelContent: some View {
        Group {
            if let error = viewModel.errorMessage, viewModel.tree == nil {
                SidebarPanelPlaceholder(
                    title: "Unable to load notes",
                    subtitle: error,
                    actionTitle: "Retry"
                ) {
                    Task { await viewModel.loadTree() }
                }
            } else if viewModel.tree == nil {
                SidebarListSkeleton(rowCount: 8, showSubtitle: false)
            } else if !viewModel.searchQuery.trimmed.isEmpty {
                searchResultsView
            } else {
                notesTreeView
            }
        }
    }

    var notesPanelContentWithArchive: some View {
        Group {
            if let error = viewModel.errorMessage, viewModel.tree == nil {
                SidebarPanelPlaceholder(
                    title: "Unable to load notes",
                    subtitle: error,
                    actionTitle: "Retry"
                ) {
                    Task { await viewModel.loadTree() }
                }
            } else if viewModel.tree == nil {
                SidebarListSkeleton(rowCount: 8, showSubtitle: false)
            } else if !viewModel.searchQuery.trimmed.isEmpty {
                searchResultsView
            } else {
                VStack(spacing: 0) {
                    notesTreeListView
                    notesArchiveSection
                }
            }
        }
    }
}
