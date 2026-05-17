import Foundation
import sideBarShared
import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - NotesPanel+Helpers

extension NotesPanelView {
    enum SelectionRequestAction: Equatable {
        case ignore
        case select
    }

    static func selectionRequestAction(
        isCompactPhone: Bool,
        currentSelectedNoteId: String?,
        activeNoteId: String?,
        requestedNoteId: String
    ) -> SelectionRequestAction {
        if isCompactPhone { return .select }
        if currentSelectedNoteId == requestedNoteId, activeNoteId == requestedNoteId {
            return .ignore
        }
        return .select
    }

    @ViewBuilder
    func notesPanelList<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        sidebarPanelList {
            content()
        }
    }

    var header: some View {
        let showsInlineSearch = ContentView.shouldShowCompactPhoneInlineSearch(
            isCompact: isCompact,
            isPhoneIdiom: isPhone
        )

        return VStack(spacing: DesignTokens.Spacing.sm) {
            PanelHeader(
                title: "Notes",
                minimumContentHeight: HeaderActionControlMetrics.chromeHeight
            ) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    if !isCompactPhone {
                        HeaderActionButton(
                            icon: AppIcon.Content.folder,
                            accessibilityLabel: "Add folder",
                            action: {
                            newFolderName = ""
                            newFolderParent = ""
                            isNewFolderPresented = true
                        },
                            chromeStyle: Self.actionControlChromeStyle
                        )
                        HeaderActionButton(
                            icon: AppIcon.Action.add,
                            accessibilityLabel: "Add note",
                            action: {
                            createBlankNote()
                        },
                            chromeStyle: Self.actionControlChromeStyle
                        )
                    }
                    if isCompact {
                        GlobalAvatarRegionControls()
                    }
                }
            }
            if showsInlineSearch {
                SearchField(text: $viewModel.searchQuery, placeholder: "Search notes", isFocused: $isSearchFocused)
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.bottom, DesignTokens.Spacing.sm)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: LayoutMetrics.searchablePanelHeaderMinHeight(showsInlineSearch: showsInlineSearch),
            alignment: .top
        )
        .sidebarPanelHeaderBackground(showsInlineSearch: showsInlineSearch)
    }

    var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    var isCompactPhone: Bool {
        isCompact && isPhone
    }

    private var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    var folderOptions: [NotesFolderOption] {
        NotesFolderOption.build(from: viewModel.tree?.children ?? [])
    }

    func createBlankNote() {
        guard !isCreatingNote else { return }
        isCreatingNote = true
        Task {
            _ = await environment.notesRuntime.createBlankNoteAndEnterEditMode()
            await MainActor.run {
                isCreatingNote = false
            }
        }
    }

    func createBlankNoteFromDeepLink() {
        guard !isCreatingNote else { return }
        isCreatingNote = true
        Task {
            _ = await environment.notesRuntime.createBlankNoteAndEnterEditMode()
            await MainActor.run {
                isCreatingNote = false
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
        "Rename folder"
    }

    var renameDialogPlaceholder: String {
        "Folder name"
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
        let action = Self.selectionRequestAction(
            isCompactPhone: isCompactPhone,
            currentSelectedNoteId: viewModel.selectedNoteId,
            activeNoteId: viewModel.activeNote?.path,
            requestedNoteId: id
        )
        guard action != .ignore else { return }
        if isCompactPhone {
            environment.notesPhoneDetailRouteId = id
        }
        Task {
            await environment.notesRuntime.editorViewModel.saveIfNeeded()
            await viewModel.selectNote(id: id)
        }
    }

    var searchResultsView: some View {
        notesPanelList {
            Section {
                if let error = viewModel.errorMessage,
                   !viewModel.searchQuery.trimmed.isEmpty {
                    SidebarPanelPlaceholder(
                        title: "Search failed",
                        subtitle: error,
                        actionTitle: "Retry",
                        style: .error
                    ) {
                        viewModel.updateSearch(query: viewModel.searchQuery)
                    }
                } else if viewModel.isSearching {
                    HStack(spacing: 12) {
                        LoadingIndicatorView(size: LoadingIndicatorSize.inline)
                        Text("Searching…")
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if viewModel.searchResults.isEmpty {
                    Text("No matching notes.")
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.searchResults, id: \.path) { node in
                        searchResultRow(for: node)
                    }
                }
            } header: {
                sidebarProminentSectionHeader("Results")
            }
        }
        .sidebarPanelListStyle(reducesCompactPhoneSectionHeaderGap: isCompactPhone)
        .sidebarCompactPhoneTopPadding(
            LayoutMetrics.compactPhoneSectionedPanelTopPaddingAdjustment,
            isCompactPhone: isCompactPhone
        )
        .scrollContentBackground(.hidden)
        .sidebarPanelListBackground()
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
            isSelected: viewModel.selectedNoteId == node.path,
            onSelect: {
                requestNoteSelection(id: node.path)
            },
            onRename: nil,
            onDelete: {
                confirmDelete(for: item)
            }
        )
        .platformContextMenu(items: noteContextMenuItemsList(for: item))
    }

    var notesPanelContent: some View {
        Group {
            if let error = viewModel.treeLoadState.errorMessage, viewModel.tree == nil {
                SidebarPanelPlaceholder(
                    title: "Unable to load notes",
                    subtitle: error,
                    actionTitle: "Retry",
                    style: .error
                ) {
                    Task { await viewModel.loadTree() }
                }
            } else if viewModel.tree == nil {
                SidebarListSkeleton(rowCount: 8, showSubtitle: false)
            } else if panelState == .empty {
                let emptyState = EmptyStateContent.noContentYet(
                    title: "No notes yet",
                    subtitle: "Create a note to get started.",
                    icon: AppIcon.Domain.notes
                )
                EmptyStateView(
                    title: emptyState.title,
                    subtitle: emptyState.subtitle,
                    icon: emptyState.icon
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(panelBackground)
            } else if !viewModel.searchQuery.trimmed.isEmpty {
                searchResultsView
            } else {
                notesTreeView
            }
        }
    }
}
